from .payload import (
    find_payload, decode_payload, is_hercules,
    find_bytecode_encoder_payload, decode_bytecode_encoder,
)
from .deserializer import deserialize, Chunk
from .disassembler import disassemble
from .decompiler import decompile
from . import lua54_bytecode
from . import lua54_disassembler
from . import lua54_decompiler
from . import source_formatter
from . import vm_decompiler_v2
from dataclasses import dataclass
from typing import Optional, List

@dataclass
class DeobfResult:
    success: bool
    mode: str
    output: str
    error: Optional[str] = None
    chunk: Optional[Chunk] = None
    stats: Optional[dict] = None

def _extract_embedded_source(chunk: Chunk) -> Optional[str]:

    src = getattr(chunk, "source", None)
    if not src:
        return None

    if src.startswith("@"):

        return None
    if src.startswith("="):
        src = src[1:]

    if not any(kw in src for kw in ("function", "local", "end", "return", "do", "if ")):
        return None
    return src

def deobfuscate(src: str, prefer: str = "decompiled") -> DeobfResult:

    if not is_hercules(src):
        return DeobfResult(
            success=False, mode="skipped", output="",
            error="Input does not look like a Hercules-obfuscated file.",
        )

    payload = find_payload(src)
    if payload is not None:
        _, _, encoded_str, charset_str, _ = payload
        try:
            raw_bytes = decode_payload(encoded_str, charset_str)
        except Exception as e:
            return DeobfResult(
                success=False, mode="skipped", output="",
                error=f"Failed to decode VM payload: {e}",
            )
        try:
            chunk = deserialize(raw_bytes)
        except Exception as e:
            return DeobfResult(
                success=False, mode="skipped", output="",
                error=f"Failed to deserialize bytecode: {e}",
            )
        return _emit(chunk, raw_bytes, prefer, payload_kind="VM")

    be_payload = find_bytecode_encoder_payload(src)
    if be_payload is not None:
        hex_str, offset, _ = be_payload
        try:
            raw_bytes = decode_bytecode_encoder(hex_str, offset)
        except Exception as e:
            return DeobfResult(
                success=False, mode="skipped", output="",
                error=f"Failed to decode BytecodeEncoder payload: {e}",
            )
        if not lua54_bytecode.looks_like_lua54_bytecode(raw_bytes):
            return DeobfResult(
                success=False, mode="skipped", output="",
                error="BytecodeEncoder payload decoded but does not look like Lua 5.4 bytecode.",
            )
        try:
            chunk = lua54_bytecode.parse(raw_bytes)
        except Exception as e:
            return DeobfResult(
                success=False, mode="skipped", output="",
                error=f"Failed to parse Lua 5.4 bytecode: {e}",
            )
        return _emit(chunk, raw_bytes, prefer, payload_kind="BytecodeEncoder")

    return DeobfResult(
        success=False, mode="skipped", output="",
        error="Hercules watermark detected but no VM or BytecodeEncoder payload found.",
    )

def _emit(chunk: Chunk, raw_bytes: bytes, prefer: str, payload_kind: str) -> DeobfResult:

    stats = {
        "raw_bytes": len(raw_bytes),
        "top_instrs": len(chunk.Instructions),
        "top_consts": len(chunk.Constants),
        "top_protos": len(chunk.Protos),
        "payload_kind": payload_kind,
    }

    if payload_kind == "BytecodeEncoder":

        if prefer != "disassembly":
            embedded = _extract_embedded_source(chunk)
            if embedded is not None:

                vm_payload = find_payload(embedded)
                if vm_payload is not None:

                    _, _, vm_encoded, vm_charset, _ = vm_payload
                    try:
                        vm_raw = decode_payload(vm_encoded, vm_charset)
                        vm_chunk = deserialize(vm_raw)

                        vm_result = _emit(vm_chunk, vm_raw, prefer, payload_kind="VM")

                        header = (
                            "-- Decompiled by deobfhercules (nested VM-in-BytecodeEncoder path)\n"
                            "-- Recovery method: BE-extract source → detect VM payload → decode VM bytecode → decompile\n"
                            f"-- Outer BytecodeEncoder raw: {len(raw_bytes)} bytes\n"
                            f"-- Embedded VM-runtime source: {len(embedded)} bytes\n"
                            f"-- Inner VM bytecode raw: {len(vm_raw)} bytes\n"
                            f"-- VM top-level: {len(vm_chunk.Instructions)} instructions, "
                            f"{len(vm_chunk.Constants)} constants, {len(vm_chunk.Protos)} sub-protos\n\n"
                        )
                        return DeobfResult(
                            success=True, mode=vm_result.mode,
                            output=header + vm_result.output,
                            chunk=vm_chunk,
                            stats={
                                "raw_bytes": len(vm_raw),
                                "top_instrs": len(vm_chunk.Instructions),
                                "top_consts": len(vm_chunk.Constants),
                                "top_protos": len(vm_chunk.Protos),
                                "payload_kind": "VM-in-BytecodeEncoder",
                                "outer_be_bytes": len(raw_bytes),
                                "embedded_source_bytes": len(embedded),
                            },
                        )
                    except Exception as e:

                        pass

                try:
                    formatted = source_formatter.format_lua(embedded)
                except Exception:
                    formatted = embedded
                stats["embedded_source_bytes"] = len(embedded)
                header = (
                    "-- Decompiled by deobfhercules (Lua 5.4 BytecodeEncoder path)\n"
                    "-- Recovery method: extracted embedded source from Proto.source\n"
                    f"-- Embedded source: {len(embedded)} bytes\n"
                    f"-- Bytecode chunk: {len(chunk.Instructions)} instructions, "
                    f"{len(chunk.Constants)} constants, {len(chunk.Protos)} sub-protos\n"
                    f"-- Raw bytecode: {len(raw_bytes)} bytes\n\n"
                )
                return DeobfResult(
                    success=True, mode="source", output=header + formatted,
                    chunk=chunk, stats=stats,
                )

        if prefer == "disassembly":
            out = lua54_disassembler.disassemble(chunk)
            return DeobfResult(success=True, mode="disassembly", output=out, chunk=chunk, stats=stats)
        try:
            out = lua54_decompiler.decompile(chunk)
            header = (
                "-- Decompiled by deobfhercules (Lua 5.4 BytecodeEncoder path)\n"
                "-- Recovery method: structural bytecode decompilation (fallback)\n"
                "-- Note: no embedded source was found in the bytecode chunk.\n"
                f"-- Top-level: {len(chunk.Instructions)} instructions, "
                f"{len(chunk.Constants)} constants, {len(chunk.Protos)} sub-protos\n"
                f"-- Raw bytecode: {len(raw_bytes)} bytes\n\n"
            )
            return DeobfResult(success=True, mode="decompiled", output=header + out, chunk=chunk, stats=stats)
        except Exception as e:
            import traceback
            tb = traceback.format_exc()
            out = lua54_disassembler.disassemble(chunk)
            return DeobfResult(
                success=True, mode="disassembly", output=out, chunk=chunk, stats=stats,
                error=f"Lua 5.4 decompiler crashed, fell back to disassembly: {e}\n{tb}",
            )

    else:

        if prefer == "disassembly":
            out = disassemble(chunk)
            return DeobfResult(success=True, mode="disassembly", output=out, chunk=chunk, stats=stats)

        try:
            out = decompile(chunk)
            if out and len(out.strip()) > 50:
                return DeobfResult(success=True, mode="decompiled", output=out, chunk=chunk, stats=stats)
        except Exception:
            pass

        try:
            out = vm_decompiler_v2.decompile_v2(chunk)
            return DeobfResult(success=True, mode="decompiled", output=out, chunk=chunk, stats=stats)
        except Exception as e:
            import traceback
            tb = traceback.format_exc()

            try:
                out = disassemble(chunk)
                return DeobfResult(
                    success=True, mode="disassembly", output=out, chunk=chunk, stats=stats,
                    error=f"Both decompilers failed, fell back to disassembly: {e}\n{tb}",
                )
            except Exception as e2:
                return DeobfResult(
                    success=False, mode="skipped", output="",
                    error=f"All decompilers failed: {e}\n{e2}",
                )

def deobfuscate_file(input_path: str, output_path: str, prefer: str = "decompiled") -> DeobfResult:

    with open(input_path, "r", encoding="utf-8", errors="replace") as f:
        src = f.read()
    result = deobfuscate(src, prefer=prefer)
    if result.success and result.output:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(result.output)
    return result

def _fmt_const_for_summary(v) -> str:

    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return str(int(v))
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):

        out = ['"']
        for ch in v:
            if ch == '"':
                out.append('\\"')
            elif ch == "\\":
                out.append("\\\\")
            elif ch == "\n":
                out.append("\\n")
            elif ch == "\r":
                out.append("\\r")
            elif ch == "\t":
                out.append("\\t")
            elif 32 <= ord(ch) < 127:
                out.append(ch)
            else:
                out.append(f"\\{ord(ch)}")
        out.append('"')
        return "".join(out)
    return repr(v)

def _build_constant_summary(chunk: Chunk, depth: int = 0, max_depth: int = 3) -> str:

    if depth > max_depth:
        return ""
    lines: List[str] = []
    prefix = "--   " + ("  " * depth)
    if depth == 0:
        label = "top-level"
    else:
        label = f"sub-proto depth {depth}"
    if chunk.Constants:
        lines.append(f"{prefix}{label} ({len(chunk.Constants)} constants):")
        for i, c in enumerate(chunk.Constants):
            lines.append(f"{prefix}  K{i}: {_fmt_const_for_summary(c)}")
    for sub in chunk.Protos:
        sub_lines = _build_constant_summary(sub, depth + 1, max_depth)
        if sub_lines:
            lines.append(sub_lines)
    return "\n".join(lines) + ("\n" if lines else "")
