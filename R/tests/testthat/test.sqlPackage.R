# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

context("Tests for sqlmlutils package management")
library(sqlmlutils)

setup({
})

teardown({
})


helper_getSetting <- function(key)
{
    settings <- c(connectionString="Driver=SQL Server;Server=TODO;Database=RevoTestDB;Trusted_Connection=True",
                  repoAddress = paste0('file:', file.path('TODO/packages/PkgsRepo'))
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
helper_remote.require <- function(pkgName)
{
    return (suppressWarnings((sqlmlutils:::sqlRemoteExecuteFun(helper_getSetting("connectionString"), require, package = pkgName, useRemoteFun = TRUE ))))
}

helper_checkPackageStatusRequire <- function(pkgName, expectedInstallStatus)
{
    requireStatus <-helper_remote.require(pkgName)
    msg <- sprintf(" %s is present : %s (expected=%s)\r\n", pkgName, requireStatus, expectedInstallStatus)
    cat("\nCHECK:", msg)
    expect_equal(expectedInstallStatus, requireStatus, info=msg)
}

helper_checkSqlLibPaths <- function(sqlLibPaths, minimumCount)
{
    cat(paste0(sqlLibPaths, colapse = "\r\n"))
    expect_true(length(sqlLibPaths) >= minimumCount)
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
    versionClass <- RevoScaleR:::rxCheckPackageManagementVersion(connectionString = helper_getSetting("connectionString"))
    expect_equal(versionClass, "ExtLib")
})


test_that("dbo cannot install package into private scope", {
    skip_if(helper_isServerLinux(), "Linux tests do not have support for Trusted user." )

    repoAddress <- helper_getSetting("repoAddress")
    pkgName <- c("glue")

    cat(sprintf("\nINFO: installing package from repo %s...\n", repoAddress))
    expect_error()
    output <- try(capture.output(sql_install.packages(connectionString = helper_getSetting("connectionString"), pkgName, verbose = TRUE, repos = repoAddress, scope="private")))
    expect_true(inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Permission denied for installing packages on SQL server for current user", output)))
    helper_checkPackageStatusRequire( pkgName, FALSE)
})

test_that( "successfull install and remove of package with special char in name that requires [] in t-sql", {

    #set scope to public for trusted connection on Windows
    scope <- if(!helper_isServerLinux()) "public" else "private"

    repoAddress <- helper_getSetting("repoAddress")
    pkgName <- c("as.color")
    connectionString <- helper_getSetting("connectionString")

    #
    # remove old packages if any and verify they aren't there
    #
    if (helper_remote.require(pkgName) == TRUE)
    {
        cat("\nINFO: removing package...\n")
        sql_remove.packages(connectionString, pkgName, verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire(pkgName, FALSE)

    #
    # install single package (package has no dependencies)
    #
    cat(sprintf("\nINFO: installing package from repo %s...\n", repoAddress))
    output <- try(capture.output(sql_install.packages(connectionString, pkgName, verbose = TRUE, repos = repoAddress, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire(pkgName, TRUE)

    #
    # remove the installed package and check again they are gone
    #
    cat("\nINFO: removing package...\n")
    output <- try(capture.output(sql_remove.packages(connectionString, pkgName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire(pkgName, FALSE)
})

test_that("test.RxInSqlServer.Acceptance.PackageInstallUninstallSingle", {
    #set scope to public for trusted connection on Windows
    scope <- if(!helper_isServerLinux())"public" else "private"

    "remoteLibPaths" <- function()
    {
        return (.libPaths())
    }

    connectionString <- helper_getSetting("connectionString")
    repoAddress <- helper_getSetting("repoAddress")
    pkgName <- c("glue")

    #
    # check package management is installed
    #
    cat("checking remote lib paths...\n")
    helper_checkSqlLibPaths(sqlLibPaths = sqlmlutils:::sqlRemoteExecuteFun(connectionString, remoteLibPaths ), 1)

    #
    # remove old packages if any and verify they aren't there
    #
    if (helper_remote.require(pkgName) == TRUE)
    {
        cat("\nINFO: removing package...\n")
        sql_remove.packages(connectionString, pkgName, verbose = TRUE, scope = scope)
    }
    helper_checkPackageStatusRequire(pkgName, FALSE)

    #
    # install single package (package has no dependencies)
    #
    cat(sprintf("\nINFO: installing package from repo %s...\n", repoAddress))
    output <- try(capture.output(sql_install.packages( connectionString, pkgName, verbose = TRUE, repos = repoAddress, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire(pkgName, TRUE)
    helper_checkSqlLibPaths(sqlLibPaths = sqlmlutils:::sqlRemoteExecuteFun(connectionString, remoteLibPaths ), 2)

    #
    # remove the installed package and check again they are gone
    #
    cat("\nINFO:removing package...\n")
    output <- try(capture.output(sql_remove.packages( connectionString, pkgName, verbose = TRUE, scope = scope)))
    print(output)
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire(pkgName, FALSE)
})
