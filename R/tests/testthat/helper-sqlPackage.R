# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(methods)
library(testthat)

Settings <- NULL

helper_parseConnectionString <- function(connectionString)
{
    # parse a connection string (e.g. "Server=localhost;Database=AirlineTestDB;Uid=AirlineUserdbowner;Pwd=****")
    # into a list with names-value pair of the parameters
    paramList <- unlist(strsplit(connectionString, ";"))
    paramsSplit <- do.call("rbind", strsplit(paramList, "="))
    params <- as.list(paramsSplit[,2])
    names(params) <- paramsSplit[,1]
    params
}

helper_getSetting <- function(key)
{
    if(is.null(Settings))
    {
        testArgs <- options('TestArgs')$TestArgs
        connectionStringDBO <- testArgs$connectionString
        connSplit <- helper_parseConnectionString( connectionStringDBO )
        connectionStringAirlineUserdbowner <- sprintf("Driver=%s;Server=%s;Database=%s;Uid=AirlineUserdbowner;Pwd=%s", connSplit$Driver, connSplit$Server, connSplit$Database, testArgs$pwdAirlineUserdbowner)
        connectionStringAirlineUser <- sprintf("Driver=%s;Server=%s;Database=%s;Uid=AirlineUser;Pwd=%s", connSplit$Driver, connSplit$Server, connSplit$Database, testArgs$pwdAirlineUser)

        Settings <<- c(connectionStringDBO = connectionStringDBO,
                 connectionStringAirlineUserdbowner = connectionStringAirlineUserdbowner,
                 connectionStringAirlineUser = connectionStringAirlineUser
               )

    }

    if( key %in% names(Settings)) return (Settings[[key]])
    stop(sprintf("setting not found: (%s)", key))
}

helper_isLinux <- function()
{
    return(Revo.version$os == "linux-gnu");
}

helper_isServerLinux <- function()
{
    return (sqlmlutils:::sqlRemoteExecuteFun(helper_getSetting("connectionStringDBO"), helper_isLinux, languageName="R"))
}

#
# Remote require
#
helper_remote.require <- function(connectionString, packageName)
{
    return (suppressWarnings((sqlmlutils:::sqlRemoteExecuteFun(connectionString, require, package = packageName, useRemoteFun = TRUE , languageName="R"))))
}

helper_checkPackageStatusRequire <- function(connectionString, packageName, expectedInstallStatus)
{
    requireStatus <- helper_remote.require( connectionString, packageName)
    msg <- sprintf(" %s is present : %s (expected=%s)\r\n", packageName, requireStatus, expectedInstallStatus)
    cat("\nCHECK:", msg)
    expect_equal(expectedInstallStatus, requireStatus, info=msg)
}

#
# Remote find.package
#
helper_remote.find.package <- function(connectionString, packageName)
{
  findResult <- sqlmlutils:::sqlRemoteExecuteFun(connectionString, find.package, package = packageName, quiet = TRUE, useRemoteFun = TRUE, languageName="R" )

  return (is.character(findResult) && (length(findResult) > 0))
}

helper_checkPackageStatusFind <- function(connectionString, packageName, expectedInstallStatus)
{
  findStatus <- helper_remote.find.package(connectionString, packageName)
  msg <- sprintf(" %s is present : %s (expected=%s)\r\n", packageName, findStatus, expectedInstallStatus)
  cat("\nCHECK:", msg)
  expect_equal(expectedInstallStatus, findStatus, msg)
}

helper_checkSqlLibPaths <- function(connectionString, minimumCount)
{
    sqlLibPaths = sqlmlutils:::sqlRemoteExecuteFun(connectionString, .libPaths, useRemoteFun = TRUE, languageName="R" )
    cat(paste0( "INFO: lib paths = ", sqlLibPaths, colapse = "\r\n"))
    expect_true(length(sqlLibPaths) >= minimumCount)
}

helper_ExecuteSQLDDL <- function(connectionString, sqlDDL)
{
    cat(sprintf("\nINFO: executing: sqlDDL=\'%s\', connectionString=\'%s\'.\r\n", substr(sqlDDL,0,256), connectionString))

    sqlmlutils:::execute(connectionString, sqlDDL)
}

helper_CreateExternalLibrary <- function(connectionString, packageName, authorization=NULL, content, languageName="R")
{
    # 1. issue 'CREATE EXTERNAL LIBRARY'
    createExtLibDDLString = paste0("CREATE EXTERNAL LIBRARY [", packageName, "]")
    if (!is.null(authorization))
    {
        createExtLibDDLString = paste0(createExtLibDDLString, " AUTHORIZATION ", authorization)
    }

    if (substr(content, 0, 2) == "0x")
    {
        createExtLibDDLString = paste0(createExtLibDDLString, " FROM (content = ", content, ") WITH (LANGUAGE = '", languageName,"')")
    }
    else
    {
        createExtLibDDLString = paste0(createExtLibDDLString, " FROM (content = '", content, "') WITH (LANGUAGE = '", languageName,"')")
    }

    helper_ExecuteSQLDDL(connectionString = connectionString, sqlDDL = createExtLibDDLString)
}

helper_callDummySPEES <- function(connectionString, languageName="R")
{
    cat(sprintf("\nINFO: call dummy sp_execute_external_library to trigger install.\r\n"))
    speesStr = paste0("EXECUTE sp_execute_external_script
    @LANGUAGE = N'", languageName,"',
    @SCRIPT = N'invisible(NULL)'")

    sqlmlutils:::execute(connectionString, speesStr)
}

#
# Returns list with 'value' and 'warning'
# In the case of a warning returns the computed result in 'value' and the warning message in 'warning'
# In the case of error returns error message in 'value' and marks it of class 'try-error'
#
helper_tryCatchValue <- function(expr)
{
    warningSave <- c()
    warningHandler <- function(w)
    {
        warningSave <<- c(warningSave, w$message)
        invokeRestart("muffleWarning")
    }

    list( value = withCallingHandlers(
        tryCatch(
            expr,
            error = function(e)
            {
                invisible(structure(conditionMessage(e), class = "try-error"))
            }
        ),
        warning = warningHandler
        ),
        warning = warningSave
    )
}

helper_cleanAllExternalLibraries <- function(connectionString)
{
  names <- sqlmlutils:::execute(connectionString, "select * from sys.external_libraries where Language = 'R'")$name
  for(name in names)
  {
    sqlmlutils:::execute(connectionString, paste0("DROP EXTERNAL LIBRARY ", name))
  }
}
