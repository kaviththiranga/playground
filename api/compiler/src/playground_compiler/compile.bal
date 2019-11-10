import ballerina/file;
import ballerina/filepath;
import ballerina/io;
import ballerina/log;

const buildCacheDir = "/build-cache";

# Create a directory for the given source in build cache dir
# and create new file containing given source.
#
# + cacheId - cacheId Cache ID for the given source
# + sourceCode - sourceCode
# + return - Absolute path of the created file or an error
# 
function createSourceFile(string cacheId, string sourceCode) returns string|error {
    if (file:exists(buildCacheDir)) {
        log:printDebug("Build cache is mounted. " );
        string cachedBuildDir = check filepath:build(buildCacheDir, cacheId);
        string cachedAppPath = check filepath:build(buildCacheDir, cacheId, "app.bal");
        if (!file:exists(cachedBuildDir)) {
            log:printDebug("Creating source file for compilation. " + cachedAppPath);
            io:WritableByteChannel appFile = check io:openWritableFile(cachedAppPath);
            _ = check appFile.write(sourceCode.toBytes(), 0);
            check appFile.close();
        } else {
            log:printDebug("Found existing source file for compilation. " + cachedAppPath);
        }
        return cachedAppPath;
    } else {
        log:printError("Build cache is not mounted. " );
        return file:FileNotFoundError( message = "Build Cache Directory " + buildCacheDir + " not found.");
    }
}

function compile(CompileData data) returns CompilerResponse|error {
    log:printDebug("Compiling request: " + data.toString());
    string? cacheId = getCacheId(data.sourceCode, data.balVersion);
    if (cacheId is string) {
        boolean hasCachedOutputResult = hasCachedOutput(cacheId);
        log:printDebug("Searching for cached output. Cache ID: " + cacheId);
        if (hasCachedOutputResult) {
            string? cachedOutput = getCachedOutput(cacheId);
            if (cachedOutput is string) {
                log:printDebug("Found cached output. " + cachedOutput);
                return createDataResponse(cachedOutput);
            } else {
                log:printError("Empty cached output returned. " );
                return createErrorResponse("Invalid cached output returned from cache.");
            }
        } else {
            log:printDebug("Cached output not found.");
            string sourceFile = check createSourceFile(cacheId, data.sourceCode);
            string buildDir = check filepath:parent(sourceFile);
            log:printDebug("Using " + sourceFile + " for compilation.");
            string|error execStatus = execBallerinaCmd(buildDir, "build", "app.bal");
            if (execStatus is error) {
                log:printError("Error while executing compile command. ", execStatus);
                return createErrorResponse(execStatus.reason());
            } else {
                log:printDebug("Finished executing compile command. Output: " + execStatus);
                string jarPath = check filepath:build(buildDir, "app.jar");
                setCachedOutput(cacheId, execStatus);
                return createDataResponse(execStatus);
            }
        }
    } else {
        return createErrorResponse("Cannot access cache");
    }
}

function createStringResponse(CompilerResponse reponse) returns string|error {
    json jsonResp = check json.constructFrom(reponse);
    return jsonResp.toJsonString();
}

function createControlResponse(string data) returns CompilerResponse {
    return <CompilerResponse> { "type": ControlResponse, "data": data };
}


function createDataResponse(string data) returns CompilerResponse {
    return <CompilerResponse> { "type": DataResponse, "data": data };
}

function createErrorResponse(string data) returns CompilerResponse {
    return <CompilerResponse> { "type": ErrorResponse, "data": data };
}