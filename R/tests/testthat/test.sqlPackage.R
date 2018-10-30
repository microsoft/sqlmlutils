# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

context("Tests for sqlmlutils package management")
library(RODBC)
library(RODBCext)
library(sqlmlutils)

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
    connectionStringDBO <- TestArgs$connectionString
    connSplit <- helper_parseConnectionString( connectionStringDBO )
    connectionStringRevoTester <- sprintf("Driver=%s;Server=%s;Database=%s;Uid=RevoTester;Pwd=%s", connSplit$Driver, connSplit$Server, connSplit$Database, TestArgs$pwdRevoTester)
    connectionStringPkgprivateextlib <- sprintf("Driver=%s;Server=%s;Database=%s;Uid=pkgprivateextlib;Pwd=%s", connSplit$Driver, connSplit$Server, connSplit$Database, TestArgs$pwdPkgPrivateExtLib)

    settings <- c(connectionStringDBO = connectionStringDBO,
                  connectionStringRevoTester = connectionStringRevoTester,
                  connectionStringPkgprivateextlib = connectionStringPkgprivateextlib
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
    return (sqlmlutils:::sqlRemoteExecuteFun(helper_getSetting("connectionStringDBO"), helper_isLinux))
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

#
# Remote find.package
#
helper_remote.find.package <- function(connectionString, packageName)
{
  findResult <- sqlmlutils:::sqlRemoteExecuteFun(connectionString, find.package, package = packageName, quiet = TRUE, useRemoteFun = TRUE )

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

    versionClass <- RevoScaleR:::rxCheckPackageManagementVersion(connectionString = helper_getSetting("connectionStringDBO"))
    expect_equal(versionClass, "ExtLib")
})


test_that("dbo cannot install package into private scope", {
    #skip("temporaly_disabled")
    skip_if(helper_isServerLinux(), "Linux tests do not have support for Trusted user." )

    packageName <- c("glue")

    output <- try(capture.output(sql_install.packages(connectionString = helper_getSetting("connectionStringDBO"), packageName, verbose = TRUE, scope="private")))
    expect_true(inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Permission denied for installing packages on SQL server for current user", output)))
    helper_checkPackageStatusRequire( connectionString,  packageName, FALSE)
})

test_that( "successfull install and remove of package with special char in name that requires [] in t-sql", {
    #skip("temporaly_disabled")

    #set scope to public for trusted connection on Windows
    scope <- if(!helper_isServerLinux()) "public" else "private"

    packageName <- c("as.color")
    connectionStringDBO <- helper_getSetting("connectionStringDBO")

    #
    # remove old packages if any and verify they aren't there
    #
    if (helper_remote.require( connectionStringDBO, packageName) == TRUE)
    {
        cat("\nINFO: removing package...\n")
        sql_remove.packages(connectionStringDBO, packageName, verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire( connectionStringDBO, packageName, FALSE)

    #
    # install single package (package has no dependencies)
    #
    output <- try(capture.output(sql_install.packages(connectionStringDBO, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringDBO, packageName, TRUE)

    #
    # remove the installed package and check again they are gone
    #
    cat("\nINFO: removing package...\n")
    output <- try(capture.output(sql_remove.packages(connectionStringDBO, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringDBO, packageName, FALSE)
})

test_that("single package install and removal with no dependencies", {
    #skip("temporaly_disabled")

    #set scope to public for trusted connection on Windows
    scope <- if(!helper_isServerLinux())"public" else "private"

    connectionStringDBO <- helper_getSetting("connectionStringDBO")
    packageName <- c("glue")

    #
    # check package management is installed
    #
    cat("checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionStringDBO, 1)

    #
    # remove old packages if any and verify they aren't there
    #
    if (helper_remote.require(connectionStringDBO, packageName) == TRUE)
    {
        cat("\nINFO: removing package...\n")
        sql_remove.packages(connectionStringDBO, packageName, verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire( connectionStringDBO, packageName, FALSE)

    #
    # install single package (package has no dependencies)
    #
    output <- try(capture.output(sql_install.packages( connectionStringDBO, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringDBO, packageName, TRUE)
    helper_checkSqlLibPaths(connectionStringDBO, 2)

    #
    # remove the installed package and check again they are gone
    #
    cat("\nINFO:removing package...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringDBO, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringDBO, packageName, FALSE)
})

test_that( "package install and uninstall with dependency", {
    #skip("temporaly_disabled")
    connectionStringRevoTester <- helper_getSetting("connectionStringRevoTester")
    scope <- "private"

    #
    # check package management is installed
    #
    cat("\nINFO: checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionStringRevoTester, 1)

    packageName <- c("plyr")
    dependentPackageName <- "Rcpp"

    #
    # remove old packages if any and verify they aren't there
    #
    cat("\nINFO: removing packages...\n")
    if (helper_remote.require(connectionStringRevoTester, packageName) == TRUE)
    {
        sql_remove.packages( connectionStringRevoTester, c(packageName), verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire( connectionStringRevoTester, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionStringRevoTester, dependentPackageName, FALSE)

    #
    # install the package with its dependencies and check if its present
    #
    output <- try(capture.output(sql_install.packages( connectionStringRevoTester, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringRevoTester,  packageName, TRUE)
    helper_checkPackageStatusRequire( connectionStringRevoTester,  dependentPackageName, TRUE)
    helper_checkSqlLibPaths(connectionStringRevoTester, 2)

    #
    # remove the installed packages and check again they are gone
    #
    cat("\nINFO: removing packages...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringRevoTester, packageName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringRevoTester, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionStringRevoTester, dependentPackageName, FALSE)
})

test_that("package top level install and remove", {
    #skip("temporaly_disabled")
    connectionStringRevoTester <- helper_getSetting("connectionStringRevoTester")
    scope <- "private"

    "remoteLibPaths" <- function()
    {
        return (.libPaths())
    }

    #
    # check package management is installed
    #
    cat("checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionStringRevoTester, 1)

    packageName <- c("plyr")
    dependentPackageName <- "Rcpp"

    #
    # remove old packages if any and verify they aren't there
    #
    cat("removing packages...\n")
    if (helper_remote.require( connectionStringRevoTester, packageName) == TRUE)
    {
        sql_remove.packages( connectionStringRevoTester, packageName, verbose = TRUE, scope = scope)
    }

    # Make sure dependent package does not exist on its own
    if (helper_remote.require(connectionStringRevoTester, dependentPackageName) == TRUE)
    {
        sql_remove.packages( connectionStringRevoTester, dependentPackageName, verbose = TRUE, scope = scope)
    }

    helper_checkPackageStatusRequire( connectionStringRevoTester, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionStringRevoTester, dependentPackageName, FALSE)

    #
    # install the package with its dependencies and check if its present
    #
    output <- try(capture.output(sql_install.packages( connectionStringRevoTester, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringRevoTester, packageName, TRUE)
    helper_checkPackageStatusRequire( connectionStringRevoTester, dependentPackageName, TRUE)

    # Promote dependent package to top most by explicit installation
    cat("\nTEST: promote dependent package to top most by explicit installation...\n")
    output <- try(capture.output(sql_install.packages( connectionStringRevoTester, dependentPackageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully attributed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringRevoTester, dependentPackageName, TRUE)


    # Remove main package and make sure the dependent, now turned top most, does not being removed
    cat("\nTEST: remove main package and make sure the dependent, now turned top most, is not removed...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringRevoTester, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringRevoTester, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionStringRevoTester, dependentPackageName, TRUE)

    # Make sure promoted dependent package can be removed
    cat("\nTEST: remove dependent package previously promoted to top most...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringRevoTester, dependentPackageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringRevoTester, dependentPackageName, FALSE)
})

test_that("Package APIs interop with Create External Library", {
    #skip("temporaly_disabled")

    cat("\nINFO: test if package management interops properly with packages installed directly with CREATE EXTERNAL LIBRARY\n
      Note:\n
        packages installed with CREATE EXTERNAL LIBRARY won't have top-level attribute set in extended properties\n
        By default we will consider them top-level packages\n")

    connectionStringRevoTester <- helper_getSetting("connectionStringRevoTester")
    scope <- "private"
    packageName <- c("glue")

    cat("\nINFO: checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionStringRevoTester, 1)

    #
    # remove old packages if any and verify they aren't there
    #
    cat("\nINFO: removing packages...\n")
    if (helper_remote.require( connectionStringRevoTester, packageName) == TRUE)
    {
        sql_remove.packages( connectionStringRevoTester, packageName, verbose = TRUE, scope = scope)
    }

    helper_checkPackageStatusRequire( connectionStringRevoTester, packageName, FALSE)

    #
    # install the package with its dependencies and check if its present
    #
    repoDir <- file.path(tempdir(), "repo")
    on.exit({
        if ( dir.exists(repoDir)){
            unlink( repoDir, recursive = TRUE , force = TRUE)
        }
    })
    dir.create( repoDir, recursive =  TRUE)
    download.packages( c("glue"), destdir = repoDir, type = "win.binary" )
    pkgPath <- list.files(repoDir, pattern = "glue.+zip", full.names = TRUE, ignore.case = TRUE)
    cat(sprintf("\nTEST: install package using CREATE EXTERNAL LIBRARY: pkg=%s...\n", pkgPath))

    fileConnection = file(pkgPath, 'rb')
    pkgBin = readBin(con = fileConnection, what = raw(), n = file.size(pkgPath))
    close(fileConnection)
    pkgContent = paste0("0x", paste0(pkgBin, collapse = "") );

    output <- try(capture.output(
        helper_CreateExternalLibrary(connectionString = connectionStringRevoTester, packageName = packageName, content = pkgContent)
    ))
    expect_true(!inherits(output, "try-error"))

    output <- try(capture.output(
        helper_callDummySPEES( connectionString = connectionStringRevoTester)
    ))
    expect_true(!inherits(output, "try-error"))


    helper_checkPackageStatusFind( connectionStringRevoTester, packageName, TRUE)

    # Enumerate packages and check that package is listed as top-level
    cat("\nTEST: enumerate packages and check that package is listed as top-level...\n")
    installedPkgs <- helper_tryCatchValue( sql_installed.packages(connectionString = connectionStringRevoTester, fields=c("Package", "Attributes", "Scope")))

    expect_true(!inherits(installedPkgs$value, "try-error"))
    expect_equal(1, as.integer(installedPkgs$value['glue','Attributes']), msg=sprintf(" (expected package listed as top-level: pkg=%s)", packageName))

    # Remove package
    cat("\nTEST: remove package previously installed with CREATE EXTERNAL LIBRARY...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringRevoTester, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringRevoTester, packageName, FALSE)
})

test_that( "package install and remove by scope", {
    #skip("temporaly_disabled")
    skip_if(helper_isServerLinux(), "Linux tests do not have support for Trusted user." )

    connectionStringDBO <- helper_getSetting("connectionStringDBO")

    packageName <- c("plyr")
    dependentPackageName <- "Rcpp"

    owner <- ""
    cat("\nTEST: connection string='",connectionStringDBO,"'\n", sep="")

    cat("\nTEST: owner is set to: owner='",owner,"'\n", sep="")

    # Extract the server and database names from the connection string supplied by the execution environment
    connSplit <- helper_parseConnectionString(helper_getSetting("connectionStringDBO"))

    #
    # --- dbo user install and remove tests ---
    #

    #
    # remove packages from both public scope
    #
    cat("\nTEST: removing packages from public scope...\n")
    try(sql_remove.packages( connectionStringDBO, packageName, scope = 'public', owner = owner, verbose = TRUE))
    helper_checkPackageStatusFind(connectionStringDBO, packageName, FALSE)

    #
    # install package in public scope
    #
    cat("\nTEST: dbo: installing packages in public scope...\n")
    sql_install.packages( connectionStringDBO, packageName, scope = 'public', owner = owner, verbose = TRUE)
    helper_checkPackageStatusFind(connectionStringDBO, packageName, TRUE)

    #
    # uninstall package in public scope
    #
    cat("\nTEST: dbo: removing packages from public scope...\n")
    sql_remove.packages( connectionStringDBO, packageName, scope = 'public', owner = owner, verbose = TRUE)
    helper_checkPackageStatusFind(connectionStringDBO, packageName, FALSE)

    #
    # --- pkgprivateextlib user install and remove tests ---
    #
    connectionStringPkgprivateextlib <- helper_getSetting("connectionStringPkgprivateextlib")

    #
    # remove packages from private scope
    #
    cat("TEST: pkgprivateextlib: removing packages from private scope...\n")
    #owner <- 'pkgprivateextlib'
    try(sql_remove.packages( connectionStringPkgprivateextlib, packageName, scope = 'private', verbose = TRUE))
    helper_checkPackageStatusFind(connectionStringPkgprivateextlib, packageName, FALSE)

    #
    # install package in private scope
    #
    cat("TEST: pkgprivateextlib: installing packages in private scope...\n")
    sql_install.packages( connectionStringPkgprivateextlib, packageName, scope = 'private', verbose = TRUE)
    helper_checkPackageStatusFind(connectionStringPkgprivateextlib, packageName, TRUE)

    #
    # uninstall package in private scope
    #
    cat("TEST: pkgprivateextlib: removing packages from private scope...\n")
    sql_remove.packages( connectionStringPkgprivateextlib, packageName, scope = 'private', verbose = TRUE)
    helper_checkPackageStatusFind(connectionStringPkgprivateextlib, packageName, FALSE)
})
