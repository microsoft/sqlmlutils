# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

context("Tests for sqlmlutils package management")
library(RODBC)
library(RODBCext)
library(sqlmlutils)

setup({
})

teardown({
})

helper_parseConnectionString <- function(connectionString)
{
    # parse a connection string (e.g. "Server=localhost;Database=RevoTestDB;Uid=RevoTester;Pwd=****")
    # into a list with names-value pair of the parameters
    paramList <- unlist(strsplit(connectionString, ";"))
    paramsSplit <- do.call("rbind", strsplit(paramList, "="))
    params <- as.list(paramsSplit[,2])
    names(params) <- paramsSplit[,1]
    params
}

helper_getSetting <- function(key)
{
    connectionString <- "Driver=SQL Server;Server=TODO;Database=RevoTestDB;Trusted_Connection=True"
    dbSettingFromConnectionString <- helper_parseConnectionString(connectionString)
    revoTesterConnectionString <- sprintf("Driver=%s;Server=%s;Database=%s;Uid=RevoTester;Pwd=TODO", dbSettingFromConnectionString$Driver, dbSettingFromConnectionString$Server, dbSettingFromConnectionString$Database)
    repoFilePath <- file.path('TODO/PkgsRepo')

    settings <- c(connectionString = connectionString,
                  revoTesterConnectionString = revoTesterConnectionString,
                  repoUrl = paste0('file:', repoFilePath ),
                  repoAddress = repoFilePath
    )

    if( key %in% names(settings)) return (settings[[key]])
    stop(sprintf("setting not found: (%s)", key))
}

helper_isLinux <- function()
{
    return(Revo.version$os == "linux-gnu");
}

helper_isServerLinux <- function()
{
    return (sqlmlutils:::sqlRemoteExecuteFun(helper_getSetting("connectionString"), helper_isLinux))
}

#
# Remote require
#
helper_remote.require <- function(connectionString, packageName)
{
    return (suppressWarnings((sqlmlutils:::sqlRemoteExecuteFun(connectionString, require, package = packageName, useRemoteFun = TRUE ))))
}

helper_checkPackageStatusRequire <- function(connectionString, packageName, expectedInstallStatus)
{
    requireStatus <- helper_remote.require( connectionString, packageName)
    msg <- sprintf(" %s is present : %s (expected=%s)\r\n", packageName, requireStatus, expectedInstallStatus)
    cat("\nCHECK:", msg)
    expect_equal(expectedInstallStatus, requireStatus, info=msg)
}

helper_checkSqlLibPaths <- function(connectionString, minimumCount)
{
    sqlLibPaths = sqlmlutils:::sqlRemoteExecuteFun(connectionString, .libPaths, useRemoteFun = TRUE )
    cat(paste0( "INFO: lib paths = ", sqlLibPaths, colapse = "\r\n"))
    expect_true(length(sqlLibPaths) >= minimumCount)
}

helper_ExecuteSQLDDL <- function(connectionString, sqlDDL)
{
    cat(sprintf("\nINFO: executing: sqlDDL=\'%s\', connectionString=\'%s\'.\r\n", substr(sqlDDL,0,256), connectionString))
    hodbc <- odbcDriverConnect(connectionString)

    sqlExecute(hodbc, query = sqlDDL, fetch = TRUE)

    odbcClose(hodbc)
}

helper_CreateExternalLibrary <- function(connectionString, packageName, authorization=NULL, content)
{
    # 1. issue 'CREATE EXTERNAL LIBRARY'
    createExtLibDDLString = paste0("CREATE EXTERNAL LIBRARY [", packageName, "]")
    if (!is.null(authorization))
    {
        createExtLibDDLString = paste0(createExtLibDDLString, " AUTHORIZATION ", authorization)
    }

    if (substr(content, 0, 2) == "0x")
    {
        createExtLibDDLString = paste0(createExtLibDDLString, " FROM (content = ", content, ") WITH (LANGUAGE = 'R')")
    }
    else
    {
        createExtLibDDLString = paste0(createExtLibDDLString, " FROM (content = '", content, "') WITH (LANGUAGE = 'R')")
    }

    helper_ExecuteSQLDDL(connectionString = connectionString, sqlDDL = createExtLibDDLString)
}

helper_callDummySPEES <- function(connectionString)
{
    cat(sprintf("\nINFO: call dummy sp_execute_external_library to trigger install.\r\n"))
    speesStr = "EXECUTE sp_execute_external_script
    @LANGUAGE = N'R',
    @SCRIPT = N'invisible(NULL)'"

    hodbc <- odbcDriverConnect(connectionString)

    sqlExecute(hodbc, query = speesStr, fetch = TRUE)

    odbcClose(hodbc)
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


test_that("checkOwner() catches bad owner parameter input", {
    expect_equal(sqlmlutils:::checkOwner(NULL), NULL)
    expect_equal(sqlmlutils:::checkOwner(''), NULL)
    expect_equal(sqlmlutils:::checkOwner('RevoTester'), NULL)
    expect_error(sqlmlutils:::checkOwner(c('a','b')))
    expect_error(sqlmlutils:::checkOwner(1))
    expect_equal(sqlmlutils:::checkOwner('01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567'), NULL)
    expect_error(sqlmlutils:::checkOwner('012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678'))
})

test_that("Package management ExtLib", {
    #skip("temporaly_disabled")

    versionClass <- RevoScaleR:::rxCheckPackageManagementVersion(connectionString = helper_getSetting("connectionString"))
    expect_equal(versionClass, "ExtLib")
})


test_that("dbo cannot install package into private scope", {
    #skip("temporaly_disabled")
    skip_if(helper_isServerLinux(), "Linux tests do not have support for Trusted user." )

    repoUrl <- helper_getSetting("repoUrl")
    packageName <- c("glue")

    cat(sprintf("\nINFO: installing package from repo %s...\n", repoUrl))
    expect_error()
    output <- try(capture.output(sql_install.packages(connectionString = helper_getSetting("connectionString"), packageName, verbose = TRUE, repos = repoUrl, scope="private")))
    expect_true(inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Permission denied for installing packages on SQL server for current user", output)))
    helper_checkPackageStatusRequire( connectionString,  packageName, FALSE)
})

test_that( "successfull install and remove of package with special char in name that requires [] in t-sql", {
    #skip("temporaly_disabled")

    #set scope to public for trusted connection on Windows
    scope <- if(!helper_isServerLinux()) "public" else "private"

    repoUrl <- helper_getSetting("repoUrl")
    packageName <- c("as.color")
    connectionString <- helper_getSetting("connectionString")

    #
    # remove old packages if any and verify they aren't there
    #
    if (helper_remote.require( connectionString, packageName) == TRUE)
    {
        cat("\nINFO: removing package...\n")
        sql_remove.packages(connectionString, packageName, verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)

    #
    # install single package (package has no dependencies)
    #
    cat(sprintf("\nINFO: installing package from repo %s...\n", repoUrl))
    output <- try(capture.output(sql_install.packages(connectionString, packageName, verbose = TRUE, repos = repoUrl, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, TRUE)

    #
    # remove the installed package and check again they are gone
    #
    cat("\nINFO: removing package...\n")
    output <- try(capture.output(sql_remove.packages(connectionString, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)
})

test_that("single package install and removal with no dependencies", {
    #skip("temporaly_disabled")

    #set scope to public for trusted connection on Windows
    scope <- if(!helper_isServerLinux())"public" else "private"

    connectionString <- helper_getSetting("connectionString")
    repoUrl <- helper_getSetting("repoUrl")
    packageName <- c("glue")

    #
    # check package management is installed
    #
    cat("checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionString, 1)

    #
    # remove old packages if any and verify they aren't there
    #
    if (helper_remote.require(connectionString, packageName) == TRUE)
    {
        cat("\nINFO: removing package...\n")
        sql_remove.packages(connectionString, packageName, verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)

    #
    # install single package (package has no dependencies)
    #
    cat(sprintf("\nINFO: installing package from repo %s...\n", repoUrl))
    output <- try(capture.output(sql_install.packages( connectionString, packageName, verbose = TRUE, repos = repoUrl, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, TRUE)
    helper_checkSqlLibPaths(connectionString, 2)

    #
    # remove the installed package and check again they are gone
    #
    cat("\nINFO:removing package...\n")
    output <- try(capture.output(sql_remove.packages( connectionString, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)
})

test_that( "package install and uninstall with dependency", {
    #skip("temporaly_disabled")
    connectionString <- helper_getSetting("revoTesterConnectionString")
    repoUrl <- helper_getSetting("repoUrl")
    scope <- "private"

    #
    # check package management is installed
    #
    cat("\nINFO: checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionString, 1)

    packageName <- c("dplyr")
    dependentPackageName <- "tibble"

    #
    # remove old packages if any and verify they aren't there
    #
    cat("\nINFO: removing packages...\n")
    if (helper_remote.require(connectionString, packageName) == TRUE)
    {
        sql_remove.packages( connectionString, c(packageName), verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionString, dependentPackageName, FALSE)

    #
    # install the package with its dependencies and check if its present
    #
    cat(sprintf("INFO: installing packages from repo %s...\n", repoUrl))
    output <- try(capture.output(sql_install.packages( connectionString, packageName, verbose = TRUE, repos = repoUrl, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionString,  packageName, TRUE)
    helper_checkPackageStatusRequire( connectionString,  dependentPackageName, TRUE)
    helper_checkSqlLibPaths(connectionString, 2)

    #
    # remove the installed packages and check again they are gone
    #
    cat("\nINFO: removing packages...\n")
    output <- try(capture.output(sql_remove.packages( connectionString, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionString, dependentPackageName, FALSE)
})

test_that("package top level install and remove", {

    #skip("temporaly_disabled")
    connectionString <- helper_getSetting("revoTesterConnectionString")
    repoUrl <- helper_getSetting("repoUrl")
    scope <- "private"

    "remoteLibPaths" <- function()
    {
        return (.libPaths())
    }

    #
    # check package management is installed
    #
    cat("checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionString, 1)

    packageName <- c("dplyr")
    dependentPackageName <- "tibble"

    #
    # remove old packages if any and verify they aren't there
    #
    cat("removing packages...\n")
    if (helper_remote.require( connectionString, packageName) == TRUE)
    {
        sql_remove.packages( connectionString, packageName, verbose = TRUE, scope = scope)
    }

    # Make sure dependent package does not exist on its own
    if (helper_remote.require(connectionString, dependentPackageName) == TRUE)
    {
        sql_remove.packages( connectionString, dependentPackageName, verbose = TRUE, scope = scope)
    }

    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionString, dependentPackageName, FALSE)

    #
    # install the package with its dependencies and check if its present
    #
    cat(sprintf("\nTEST: install the package with its dependencies from repo %s...\n", repoUrl))
    output <- try(capture.output(sql_install.packages( connectionString, packageName, verbose = TRUE, repos = repoUrl, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, TRUE)
    helper_checkPackageStatusRequire( connectionString, dependentPackageName, TRUE)

    # Promote dependent package to top most by explicit installation
    cat("\nTEST: promote dependent package to top most by explicit installation...\n")
    output <- try(capture.output(sql_install.packages( connectionString, dependentPackageName, verbose = TRUE, repos = repoUrl, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully attributed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, dependentPackageName, TRUE)


    # Remove main package and make sure the dependent, now turned top most, does not being removed
    cat("\nTEST: remove main package and make sure the dependent, now turned top most, is not removed...\n")
    output <- try(capture.output(sql_remove.packages( connectionString, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionString, dependentPackageName, TRUE)

    # Make sure promoted dependent package can be removed
    cat("\nTEST: remove dependent package previously promoted to top most...\n")
    output <- try(capture.output(sql_remove.packages( connectionString, dependentPackageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, dependentPackageName, FALSE)
})

test_that("Package APIs interop with Create External Library", {

    #skip("temporaly_disabled")

    cat("\nINFO: test if package management interops properly with packages installed directly with CREATE EXTERNAL LIBRARY\n
      Note:\n
        packages installed with CREATE EXTERNAL LIBRARY won't have top-level attribute set in extended properties\n
        By default we will consider them top-level packages\n")

    connectionString <- helper_getSetting("revoTesterConnectionString")
    repoAddress <- helper_getSetting("repoAddress")
    scope <- "private"
    packageName <- c("glue")

    cat("\nINFO: checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionString, 1)

    #
    # remove old packages if any and verify they aren't there
    #
    cat("\nINFO: removing packages...\n")
    if (helper_remote.require( connectionString, packageName) == TRUE)
    {
        sql_remove.packages( connectionString, packageName, verbose = TRUE, scope = scope)
    }

    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)

    #
    # install the package with its dependencies and check if its present
    #
    pkgPath <- file.path(repoAddress, "bin/windows/contrib/3.4", "glue_1.1.1.zip")
    cat(sprintf("\nTEST: install package using CREATE EXTERNAL LIBRARY: pkg=%s...\n", pkgPath))

    fileConnection = file(pkgPath, 'rb')
    pkgBin = readBin(con = fileConnection, what = raw(), n = file.size(pkgPath))
    close(fileConnection)
    pkgContent = paste0("0x", paste0(pkgBin, collapse = "") );

    output <- try(capture.output(
        helper_CreateExternalLibrary(connectionString = connectionString, packageName = packageName, content = pkgContent)
    ))
    expect_true(!inherits(output, "try-error"))

    output <- try(capture.output(
        helper_callDummySPEES( connectionString = connectionString)
    ))
    expect_true(!inherits(output, "try-error"))


    helper_checkPackageStatusRequire( connectionString, packageName, TRUE)

    # Enumerate packages and check that package is listed as top-level
    cat("\nTEST: enumerate packages and check that package is listed as top-level...\n")
    installedPkgs <- helper_tryCatchValue( sql_installed.packages(connectionString = connectionString, fields=c("Package", "Attributes", "Scope")))

    expect_true(!inherits(installedPkgs$value, "try-error"))
    expect_equal(1, as.integer(installedPkgs$value['glue','Attributes']), msg=sprintf(" (expected package listed as top-level: pkg=%s)", packageName))

    # Remove package
    cat("\nTEST: remove package previously installed with CREATE EXTERNAL LIBRARY...\n")
    output <- try(capture.output(sql_remove.packages( connectionString, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionString, packageName, FALSE)
})
