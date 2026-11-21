#pragma warning disable 0162

#pragma warning disable 0219

#pragma warning disable 1591

#pragma warning disable 419

using Antlr4.Runtime.Misc;
using Antlr4.Runtime.Tree;

namespace MoonsecDeobfuscator.Syntax.Parser;

[System.CodeDom.Compiler.GeneratedCode("ANTLR", "4.13.2")]
[System.CLSCompliant(false)]
public interface ILuaVisitor<Result> : IParseTreeVisitor<Result> {

	Result VisitChunk([NotNull] LuaParser.ChunkContext context);

	Result VisitBlock([NotNull] LuaParser.BlockContext ctx);

	Result VisitStatSemi([NotNull] LuaParser.StatSemiContext context);

	Result VisitStatAssign([NotNull] LuaParser.StatAssignContext ctx);

	Result VisitStatCall([NotNull] LuaParser.StatCallContext ctx);

	Result VisitStatLabel([NotNull] LuaParser.StatLabelContext context);

	Result VisitStatBreak([NotNull] LuaParser.StatBreakContext ctx);

	Result VisitStatGoto([NotNull] LuaParser.StatGotoContext context);

	Result VisitStatDo([NotNull] LuaParser.StatDoContext ctx);

	Result VisitStatWhile([NotNull] LuaParser.StatWhileContext ctx);

	Result VisitStatRepeat([NotNull] LuaParser.StatRepeatContext ctx);

	Result VisitStatIf([NotNull] LuaParser.StatIfContext ctx);

	Result VisitStatNumericFor([NotNull] LuaParser.StatNumericForContext ctx);

	Result VisitStatGenericFor([NotNull] LuaParser.StatGenericForContext ctx);

	Result VisitStatFunction([NotNull] LuaParser.StatFunctionContext context);

	Result VisitStatLocalFunction([NotNull] LuaParser.StatLocalFunctionContext context);

	Result VisitStatLocalDeclare([NotNull] LuaParser.StatLocalDeclareContext context);

	Result VisitIfstmt([NotNull] LuaParser.IfstmtContext context);

	Result VisitElseifstmt([NotNull] LuaParser.ElseifstmtContext context);

	Result VisitElsestmt([NotNull] LuaParser.ElsestmtContext context);

	Result VisitRetstat([NotNull] LuaParser.RetstatContext context);

	Result VisitLabel([NotNull] LuaParser.LabelContext context);

	Result VisitFuncname([NotNull] LuaParser.FuncnameContext context);

	Result VisitVarlist([NotNull] LuaParser.VarlistContext context);

	Result VisitNamelist([NotNull] LuaParser.NamelistContext context);

	Result VisitExplist([NotNull] LuaParser.ExplistContext context);

	Result VisitExpNumber([NotNull] LuaParser.ExpNumberContext context);

	Result VisitExpTrue([NotNull] LuaParser.ExpTrueContext context);

	Result VisitExpOr([NotNull] LuaParser.ExpOrContext context);

	Result VisitExpBitwise([NotNull] LuaParser.ExpBitwiseContext context);

	Result VisitExpMulDivMod([NotNull] LuaParser.ExpMulDivModContext context);

	Result VisitExpFalse([NotNull] LuaParser.ExpFalseContext context);

	Result VisitExpString([NotNull] LuaParser.ExpStringContext context);

	Result VisitExpPrefix([NotNull] LuaParser.ExpPrefixContext context);

	Result VisitExpUnary([NotNull] LuaParser.ExpUnaryContext context);

	Result VisitExpAnd([NotNull] LuaParser.ExpAndContext context);

	Result VisitExpPow([NotNull] LuaParser.ExpPowContext context);

	Result VisitExpFunction([NotNull] LuaParser.ExpFunctionContext context);

	Result VisitExpCompare([NotNull] LuaParser.ExpCompareContext context);

	Result VisitExpConcat([NotNull] LuaParser.ExpConcatContext context);

	Result VisitExpNil([NotNull] LuaParser.ExpNilContext context);

	Result VisitExpAddSub([NotNull] LuaParser.ExpAddSubContext context);

	Result VisitExpVarArg([NotNull] LuaParser.ExpVarArgContext context);

	Result VisitExpTable([NotNull] LuaParser.ExpTableContext context);

	Result VisitPrefixexp([NotNull] LuaParser.PrefixexpContext context);

	Result VisitFunctioncall([NotNull] LuaParser.FunctioncallContext context);

	Result VisitVarOrExp([NotNull] LuaParser.VarOrExpContext context);

	Result VisitVar([NotNull] LuaParser.VarContext context);

	Result VisitVarSuffix([NotNull] LuaParser.VarSuffixContext context);

	Result VisitNameAndArgs([NotNull] LuaParser.NameAndArgsContext context);

	Result VisitArgs([NotNull] LuaParser.ArgsContext context);

	Result VisitFunctiondef([NotNull] LuaParser.FunctiondefContext context);

	Result VisitFuncbody([NotNull] LuaParser.FuncbodyContext context);

	Result VisitParlist([NotNull] LuaParser.ParlistContext context);

	Result VisitTableconstructor([NotNull] LuaParser.TableconstructorContext context);

	Result VisitFieldlist([NotNull] LuaParser.FieldlistContext context);

	Result VisitField([NotNull] LuaParser.FieldContext context);

	Result VisitFieldsep([NotNull] LuaParser.FieldsepContext context);

	Result VisitOperatorOr([NotNull] LuaParser.OperatorOrContext context);

	Result VisitOperatorAnd([NotNull] LuaParser.OperatorAndContext context);

	Result VisitOperatorComparison([NotNull] LuaParser.OperatorComparisonContext context);

	Result VisitOperatorStrcat([NotNull] LuaParser.OperatorStrcatContext context);

	Result VisitOperatorAddSub([NotNull] LuaParser.OperatorAddSubContext context);

	Result VisitOperatorMulDivMod([NotNull] LuaParser.OperatorMulDivModContext context);

	Result VisitOperatorBitwise([NotNull] LuaParser.OperatorBitwiseContext context);

	Result VisitOperatorUnary([NotNull] LuaParser.OperatorUnaryContext context);

	Result VisitOperatorPower([NotNull] LuaParser.OperatorPowerContext context);

	Result VisitNumber([NotNull] LuaParser.NumberContext context);

	Result VisitString([NotNull] LuaParser.StringContext context);
}
