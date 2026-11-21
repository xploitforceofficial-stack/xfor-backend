throwError = function(errorMessage, ...)
    error(errorMessage, 0)
    return
end

kickPlayer = function(gameServices, kickMessage, ...)
    local localPlayer
    localPlayer = gameServices.Players.LocalPlayer
    if not (not (localPlayer)) then
        localPlayer.Kick(localPlayer, kickMessage)
    end
    return
end

findKeyInTable = function(targetTable, dictionary, keyMapper, foundStatus, ...)
    local key, value, result, iterator
    iterator = nil
    while true do
        iterator, key = next(targetTable, iterator)
        if iterator == nil then
            return
        end
        if type(key) == "string" then
            result = dictionary[keyMapper(key)]
        else
            result = false
        end
        if result then
            foundStatus = true
            return
        end
        iterator = iterator
    end
end

validateEnvironment = function(gameServices, ...)
    local isDataModel, isWorkspace, isMaterialEnum, isMaterialValue, isGameChanged, isWorkspaceChanged, runService, isRunService
    local isHeartbeat, isClientOrServer, isPartInstance, isPartClassName, isWorkspaceInstance, isCFrameValid, distributedTimeStart, distributedTimeEnd
    local isTimeValid, pcallResult, pcallData, isUUIDValid, checkCount
    local isUUIDFormatValid, isUUIDStructureValid, isUUIDLengthValid, isInstanceValid
    local isMaterialValid, isCFrameValueValid, isCFrameXValid, isCFrameYValid, isCFrameZValid, isCheckResult
    isDataModel = (game.ClassName == "DataModel")
    isWorkspace = (workspace.ClassName == "Workspace")
    isMaterialEnum = (typeof(Enum.Material.Plastic) == "EnumItem")
    isMaterialValue = (Enum.Material.Plastic.Value == 256)
    isGameChanged = (typeof(game.Changed) == "RBXScriptSignal")
    isWorkspaceChanged = (typeof(workspace.Changed) == "RBXScriptSignal")
    runService = gameServices.RunService
    isRunService = (runService.ClassName == "RunService")
    isHeartbeat = (typeof(runService.Heartbeat) == "RBXScriptSignal")
    local isClient = runService.IsClient(runService)
    if runService.IsClient(runService) then
        isClientOrServer = isClient
    else
        isClientOrServer = runService.IsServer(runService)
    end
    isHeartbeat = isClientOrServer
    local tempPart = Instance.new("Part")
    local isInstance = (typeof(tempPart) == "Instance")
    if not ((typeof(tempPart) == "Instance")) then
        isPartInstance = isInstance
    else
        isPartInstance = (tempPart.ClassName == "Part")
    end
    isPartClassName = isPartInstance
    tempPart.Destroy(tempPart)
    isWorkspaceInstance = (gameServices.Workspace.ClassName == "Workspace")
    local testCFrame = CFrame.new(1, 2, 3)
    if not ((testCFrame.X == 1)) then
        isCFrameXValid = (testCFrame.X == 1)
    else
        isCFrameXValid = (testCFrame.Y == 2)
    end
    if not (isCFrameXValid) then
        isCFrameValueValid = isCFrameXValid
    else
        isCFrameYValid = isCFrameXValid
        isCFrameZValid = isCFrameYValid
        isCFrameValueValid = (testCFrame.Z == 3)
    end
    isCFrameValid = isCFrameValueValid
    distributedTimeStart = workspace.DistributedGameTime
    task.wait()
    distributedTimeEnd = workspace.DistributedGameTime
    isTimeValid = (0 < (distributedTimeEnd - distributedTimeStart))
    pcallResult, pcallData = pcall(function(...) return validateUUID(gameServices, ...) end)
    if not (pcallResult) then
        isUUIDValid = pcallResult
    else
        isUUIDValid = (#pcallData == 36)
    end
    if not (isUUIDValid) then
        isUUIDFormatValid = isUUIDValid
    else
        isUUIDStructureValid = isUUIDValid
        isUUIDLengthValid = isUUIDStructureValid
        isUUIDFormatValid = (pcallData.sub(pcallData, 9, 9) == "-")
    end
    isCheckResult = isUUIDFormatValid
    checkCount = 0
    local checkList = {}
    table.insert(checkList, isDataModel)
    table.insert(checkList, isWorkspace)
    table.insert(checkList, isMaterialEnum)
    table.insert(checkList, isMaterialValue)
    table.insert(checkList, isGameChanged)
    table.insert(checkList, isWorkspaceChanged)
    table.insert(checkList, isRunService)
    table.insert(checkList, isHeartbeat)
    table.insert(checkList, isClientOrServer)
    table.insert(checkList, isPartClassName)
    table.insert(checkList, isWorkspaceInstance)
    table.insert(checkList, isCFrameValid)
    table.insert(checkList, isTimeValid)
    table.insert(checkList, isCheckResult)
    for index, value in ipairs(checkList) do
        if not (not (value)) then
            checkCount = (checkCount + 1)
        end
    end
    if not (((checkCount)<(14))) then
        isInstanceValid = nil
    else
        isInstanceValid = true
    end
    return
end

checkNaN = function(...)
    local nanValue, isValid
    nanValue = (0 / 0)
    if not ((nanValue == nanValue)) then
        isValid = nil
    else
        isValid = true
    end
    return
end

verifyScriptContext = function(...)
    local scriptContext
    scriptContext = game.GetService(game, "ScriptContext")
    if not (not ((typeof(scriptContext) ~= "Instance"))) then
        error("", 0)
    end
    if not (not ((scriptContext.ClassName ~= "ScriptContext"))) then
        error("", 0)
    end
    return
end

validateExecutionTime = function(actionCallback, ...)
    local startTime, endTime, isTimeStable
    startTime = os.clock()
    endTime = os.clock()
    if not ((startTime == endTime)) then
        isTimeStable = (startTime == endTime)
    else
        isTimeStable = (startTime ~= 0)
    end
    if not (not (isTimeStable)) then
        actionCallback()
    end
    if not (not ((type(startTime) ~= "number"))) then
        actionCallback()
    end
    return
end

checkGlobalEnv = function(actionCallback, ...)
    if not (not (getgenv)) then
        if not (not ((getgenv() ~= getgenv()))) then
            actionCallback()
        end
    end
    return
end

validateMemStats = function(gameServices, ...)
    local animProvider, memStats, matchCount, stringCount
    animProvider = gameServices.AnimationClipProvider
    memStats = animProvider.GetMemStats(animProvider)
    stringCount = 0
    matchCount = 0
    for key, value in pairs(memStats) do
        if not (not ((type(key) == "string"))) then
            matchCount = (matchCount + 1)
        end
        if not (not ((type(value) == "number"))) then
            stringCount = (stringCount + 1)
        end
    end
    local isStatsValid
    if not ((0 < matchCount)) then
        isStatsValid = (0 < matchCount)
    else
        isStatsValid = (0 < stringCount)
    end
    local result
    if not (isStatsValid) then
        result = isStatsValid
    else
        local tempStats = isStatsValid
        local finalStats = tempStats
        result = (matchCount == stringCount)
    end
    if not (not ((not result))) then
        error("", 0)
    end
    return
end

checkDebugHook = function(actionCallback, ...)
    local hookFunction, hookData, isHookValid
    if not (debug) then
        hookData = debug
    else
        hookData = debug.gethook
    end
    if not (not (hookData)) then
        hookFunction, hookData = debug.gethook()
        if not ((hookFunction ~= nil)) then
            isHookValid = (hookFunction ~= nil)
        else
            isHookValid = (hookData ~= "")
        end
        if not (not (isHookValid)) then
            actionCallback()
        end
    end
    return
end

validateTraceback = function(actionCallback, ...)
    local tracebackFunc, isTracebackValid, statusFlag, tempVar
    if not (debug) then
        tracebackFunc = debug
    else
        tracebackFunc = debug.traceback
    end
    if not ((not tracebackFunc)) then
        local wrapper = function(...) return captureTraceback(...) end
        local checkResult = wrapper(math.abs)
        if not (wrapper(math.abs)) then
            statusFlag = checkResult
        else
            statusFlag = wrapper(string.len)
        end
        if not (statusFlag) then
            isTracebackValid = statusFlag
        else
            local varA = statusFlag
            local varB = varA
            isTracebackValid = wrapper(table.insert)
        end
        if not (not ((not isTracebackValid))) then
            actionCallback()
        end
        return
    else
        return
    end
end

captureTraceback = function(...)
    local argData, successFlag
    argData = ...
    successFlag = false
    xpcall(function(...) return executeTracebackWrapper(argData, ...) end, function(...) return verifyCFunction(...) end)
    return successFlag
end

executeTracebackWrapper = function(callback, ...)
    callback(nil)
    return
end

verifyCFunction = function(status, ...)
    local stackTrace, isCFunction
    stackTrace = debug.traceback()
    local isString = (type(stackTrace) == "string")
    if not ((type(stackTrace) == "string")) then
        isCFunction = isString
    else
        local findResult = stackTrace.find(stackTrace, "C function")
        if stackTrace.find(stackTrace, "C function") then
            isCFunction = findResult
        else
            isCFunction = stackTrace.find(stackTrace, "%[C%]")
        end
    end
    if not (not (isCFunction)) then
        status = true
    end
    return
end

setupMetatableHooks = function(flagUpdate, isComplete, ...)
    local proxyTable, metatable, dummyFunc, setterFunc
    local mtHandler = {}
    mtHandler.__index = function(...) return triggerMetatableHook(...) end
    proxyTable = setmetatable({}, mtHandler)
    if not ((proxyTable.zzz ~= 42)) then
        dummyFunc = nil
    else
        dummyFunc = true
    end
    local callHandler = {}
    callHandler.__call = function(...) return triggerCallHook(...) end
    setterFunc = dummyFunc
    local setMt = setmetatable
    local emptyT = {}
    local callMt = callHandler
    metatable = setMt(emptyT, callMt)
    local varA = setterFunc
    local varB = metatable
    if not ((varB() ~= 7)) then
        isComplete = varA
    else
        local varC = varA
        local varD = varC
        flagUpdate = true
        isComplete = varD
    end
    local newIndexHandler = {}
    newIndexHandler.__newindex = function(...) return triggerNewIndexHook(...) end
    local lockedTable = setmetatable({}, newIndexHandler)
    local varE = isComplete
    local varF = lockedTable
    local mainProxy = varF
    mainProxy.q = 1
    local varG = varE
    local rawGet = rawget
    local varH = mainProxy
    if not ((rawGet(varH, "q") ~= nil)) then
        isComplete = varG
    else
        local varI = varG
        local varJ = varI
        flagUpdate = true
        isComplete = varJ
    end
    local varK = isComplete
    local pcallFunc = pcall
    local strFormat = string.format
    local formatPattern = "%d"
    local emptyArg = {}
    if not (pcallFunc(strFormat, formatPattern, emptyArg)) then
        isComplete = varK
    else
        local varL = varK
        local varM = varL
        flagUpdate = true
        isComplete = varM
    end
    isComplete = true
    return
end

triggerMetatableHook = function(...)
    return 42
end

triggerCallHook = function(...)
    return 7
end

triggerNewIndexHook = function(...)
    return
end

checkFunctionHooks = function(actionCallback, ...)
    local hookIndex, hookValue
    if not (not (isfunctionhooked)) then
        local protectedFunctions = {}
        table.insert(protectedFunctions, rawget)
        table.insert(protectedFunctions, rawset)
        table.insert(protectedFunctions, pairs)
        table.insert(protectedFunctions, ipairs)
        table.insert(protectedFunctions, tostring)
        table.insert(protectedFunctions, type)
        table.insert(protectedFunctions, string.gsub)
        table.insert(protectedFunctions, string.format)
        table.insert(protectedFunctions, table.concat)
        for hookIndex, hookValue in ipairs(protectedFunctions) do
            if not (not (isfunctionhooked(hookValue))) then
                actionCallback()
            end
        end
    end
    return
end

scanForCanary = function(callback, ...)
    local canaryName, canaryFileAction
    if not ((type(readfile) ~= "function")) then
        local isFileFunc = type(isfile)
        if not ((isFileFunc ~= "function")) then
            canaryFileAction = (isFileFunc ~= "function")
        else
            canaryFileAction = (type(listfiles) ~= "function")
        end
        if not (canaryFileAction) then
            canaryName = ("obc" .. (tostring(math.random(1, 1000000000)) .. "canary"))
            pcall(function(...) return executeCanaryScript(canaryName, ...) end)
            local checkFile = function(...) return verifyFileContent(canaryName, callback, ...) end
            local fileNames = {}
            table.insert(fileNames, "script.lua")
            table.insert(fileNames, "dump.lua")
            table.insert(fileNames, "dumped.lua")
            table.insert(fileNames, "output.lua")
            table.insert(fileNames, "saved.lua")
            table.insert(fileNames, "source.lua")
            for index, fileName in ipairs(fileNames) do
                if type(isfile) == "function" then
                    local status, result = pcall(isfile, fileName)
                    if status and result then
                        checkFile(fileName)
                    end
                end
            end
            if not (not ((type(listfiles) == "function"))) then
                local listResult, fileList = pcall(listfiles, "")
                local isListValid
                if not (listResult) then
                    isListValid = listResult
                else
                    isListValid = (type(fileList) == "table")
                end
                if not (not (isListValid)) then
                    for idx, filePath in ipairs(fileList) do
                        local pathType = type(filePath)
                        local isLuaFile
                        if not ((pathType == "string")) then
                            isLuaFile = (pathType == "string")
                        else
                            isLuaFile = (filePath.sub(filePath, -4) == ".lua")
                        end
                        if not (not (isLuaFile)) then
                            checkFile(filePath)
                        end
                    end
                end
            end
            return
        else
            return
        end
    else
        return
    end
end

executeCanaryScript = function(canaryContent, ...)
    local loadFunc, scriptResult
    if loadstring then
        loadFunc = loadstring
    else
        loadFunc = load
    end
    local execLoader = loadFunc
    if not (not (execLoader)) then
        scriptResult = execLoader(("local " .. (canaryContent .. "=1 return 0")))
        if not (not (scriptResult)) then
            pcall(scriptResult)
        end
    end
    return
end

verifyFileContent = function(canaryString, callback, ...)
    local filePath, readStatus, fileContent, contentFound
    filePath = ...
    readStatus, fileContent = pcall(readfile, filePath)
    local isContentValid
    if not (readStatus) then
        isContentValid = readStatus
    else
        isContentValid = (type(fileContent) == "string")
    end
    if not (isContentValid) then
        contentFound = isContentValid
    else
        local tempContent = isContentValid
        local finalContent = tempContent
        contentFound = fileContent.find(fileContent, canaryString, 1, true)
    end
    if not (not (contentFound)) then
        callback()
    end
    return
end

checkExecutorIdentity = function(flagUpdate, ...)
    local executorName, getExecutor
    if identifyexecutor then
        getExecutor = identifyexecutor
    else
        getExecutor = getexecutorname
    end
    if not (getExecutor) then
        executorName = game.GetService(game, "DebuggerManager")
        if not (not ((typeof(executorName) ~= "Instance"))) then
            error("", 0)
        end
        flagUpdate = true
        return
    else
        return
    end
end

inspectMetatables = function(callback, ...)
    local inspectFunc, globalEnv
    inspectFunc = function(...) return checkTableMetatable(callback, ...) end
    if not (getgenv) then
        globalEnv = getgenv
    else
        globalEnv = getgenv()
    end
    local envTable = globalEnv
    if not (not (envTable)) then
        inspectFunc(getmetatable(envTable), true)
        if not (not (getrawmetatable)) then
            inspectFunc(getrawmetatable(envTable), true)
        end
    end
    inspectFunc(getmetatable(_G), false)
    if not (not (getrawmetatable)) then
        inspectFunc(getrawmetatable(_G), false)
    end
    return
end

checkTableMetatable = function(callback, ...)
    local targetTable, isGlobal, checkResult
    targetTable, isGlobal = ...
    if not (not ((type(targetTable) == "table"))) then
        if not (not ((rawget(targetTable, "__newindex") ~= nil))) then
            callback()
        end
        if not ((not isGlobal)) then
            checkResult = (not isGlobal)
        else
            checkResult = (rawget(targetTable, "__index") ~= nil)
        end
        if not (not (checkResult)) then
            callback()
        end
        if not (not ((rawget(targetTable, "__call") ~= nil))) then
            callback()
        end
        if not (not ((rawget(targetTable, "__pairs") ~= nil))) then
            callback()
        end
    end
    return
end

validateCharacterAppearance = function(gameServices, callback, ...)
    local pcallStatus, appearanceData, isDataValid
    pcallStatus, appearanceData = pcall(function(...) return getCharacterData(gameServices, ...) end)
    if not ((not pcallStatus)) then
        isDataValid = pcall(function(...) return verifyAssetData(appearanceData, ...) end)
        if not (not ((not isDataValid))) then
            callback()
        end
        return
    else
        return
    end
end

getCharacterData = function(gameServices, ...)
    return gameServices.Players.GetCharacterAppearanceInfoAsync(gameServices.Players, 1)
end

verifyAssetData = function(assetData, ...)
    if not (not ((type(assetData) ~= "table"))) then
        error("", 0)
    end
    if not (not ((type(assetData.assets) ~= "table"))) then
        error("", 0)
    end
    if not (not ((type(assetData.bodyColors) ~= "table"))) then
        error("", 0)
    end
    if not (not ((type(assetData.scales) ~= "table"))) then
        error("", 0)
    end
    return
end

validateCharacterInstance = function(gameServices, callback, ...)
    local localPlayer, character
    localPlayer = gameServices.Players.LocalPlayer
    local tempChar
    if not (localPlayer) then
        tempChar = localPlayer
    else
        tempChar = localPlayer.Character
    end
    character = tempChar
    if not (not ((character ~= nil))) then
        if not (not ((typeof(character) ~= "Instance"))) then
            callback()
        end
        if not (not ((not character.IsDescendantOf(character, game)))) then
            callback()
        end
    end
    return
end

checkEnvironmentIsolation = function(callback, ...)
    local envVars, envKey, envValue
    if not (not (getfenv)) then
        envVars = getfenv()
        envKey = {}
        envValue = math.floor((math.log(100, 10) * 1000000000))
        envVars[envKey] = envValue
        if not (not ((envVars[envKey] ~= envValue))) then
            callback()
        end
        envVars[envKey] = nil
    end
    return
end

validateStreamingEnabled = function(gameServices, flagUpdate, isChecked, ...)
    local workspaceService, streamingEnabledA, streamingEnabledB
    workspaceService = gameServices.Workspace
    streamingEnabledA = workspaceService.StreamingEnabled
    streamingEnabledB = workspaceService.StreamingEnabled
    if not (not ((streamingEnabledA ~= streamingEnabledB))) then
        flagUpdate = true
    end
    if not (not ((type(streamingEnabledA) ~= "boolean"))) then
        flagUpdate = true
    end
    isChecked = true
    return
end

validateHttpUrlEncoding = function(gameServices, callback, ...)
    if not (not ((gameServices.HttpService.UrlEncode(gameServices.HttpService, "a b&c") ~= "a%20b%26c"))) then
        callback()
    end
    return
end

validateHttpEnabled = function(gameServices, flagUpdate, ...)
    if not (not ((type(gameServices.HttpService.HttpEnabled) ~= "boolean"))) then
        flagUpdate = true
    end
    return
end

validateGameId = function(...)
    local gameId, isIdValid
    gameId = game.GameId
    local idTypeCheck = (type(gameId) ~= "number")
    if (type(gameId) ~= "number") then
        isIdValid = idTypeCheck
    else
        isIdValid = (0 >= gameId)
    end
    if not (not (isIdValid)) then
        error("", 0)
    end
    return
end

startSecurityLoop = function(checkA, checkB, ...)
    while true do
        if not (true) then
            break
        else
            task.wait((7 + (tick() % 6)))
            pcall(function(...) return verifyMetatableIntegrity(checkA, checkB, ...) end)
            pcall(function(...) return verifyDebugTraceback(checkB, ...) end)
            pcall(function(...) return verifyFunctionHooks(checkB, ...) end)
            continue
        end
    end
    return
end

verifyMetatableIntegrity = function(targetTable, callback, ...)
    local rawMeta, getMeta
    if not (getrawmetatable) then
        getMeta = getrawmetatable
    else
        getMeta = getrawmetatable(targetTable)
    end
    rawMeta = getMeta
    if not (not ((type(rawMeta) == "table"))) then
        if not (not ((rawget(rawMeta, "__newindex") ~= nil))) then
            callback()
        end
        if not (not ((rawget(rawMeta, "__index") ~= nil))) then
            callback()
        end
    end
    return
end

verifyDebugTraceback = function(callback, ...)
    local traceFunc, traceData, status
    if not (debug) then
        traceData = debug
    else
        traceData = debug.traceback
    end
    if not ((not traceData)) then
        traceFunc = function(...) return captureTraceback(...) end
        local checkResult = traceFunc(rawget)
        if not (traceFunc(rawget)) then
            status = checkResult
        else
            status = traceFunc(rawset)
        end
        if not (not ((not status))) then
            callback()
        end
        return
    else
        return
    end
end

verifyFunctionHooks = function(callback, ...)
    local hookIndex, hookValue
    if not (not (isfunctionhooked)) then
        local restrictedFunctions = {}
        table.insert(restrictedFunctions, rawget)
        table.insert(restrictedFunctions, rawset)
        table.insert(restrictedFunctions, pairs)
        table.insert(restrictedFunctions, next)
        table.insert(restrictedFunctions, getfenv)
        for hookIndex, hookValue in ipairs(restrictedFunctions) do
            if not (not (isfunctionhooked(hookValue))) then
                callback()
            end
        end
    end
    return
end

validateTableStructure = function(targetTable, typeChecker, indexChecker, flagResult, ...)
    local rawMeta, getMeta
    if not (getrawmetatable) then
        getMeta = getrawmetatable
    else
        getMeta = getrawmetatable(targetTable)
    end
    rawMeta = getMeta
    if not (not ((typeChecker(rawMeta) == "table"))) then
        if not (not ((indexChecker(rawMeta, "__newindex") ~= nil))) then
            flagResult = true
        end
    end
    return
end

safeSetField = function(callback, targetTable, key, value, ...)
    local status, errorMsg
    local valueA, valueB = ...
    status = pcall(callback, targetTable, valueA, valueB)
    if not (not ((not status))) then
        pcall(function(...) return performAssignment(targetTable, valueA, valueB, ...) end)
    end
    return
end

performAssignment = function(tableRef, key, value, ...)
    tableRef[key] = value
    return
end
