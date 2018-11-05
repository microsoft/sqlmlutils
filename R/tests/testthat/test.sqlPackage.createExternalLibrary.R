# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(RODBC)
library(RODBCext)
library(sqlmlutils)
library(testthat)

context("Tests for sqlmlutils package management create external library")

test_that("Package APIs interop with Create External Library", {
    #skip("temporaly_disabled")

    cat("\nINFO: test if package management interops properly with packages installed directly with CREATE EXTERNAL LIBRARY\n
      Note:\n
        packages installed with CREATE EXTERNAL LIBRARY won't have top-level attribute set in extended properties\n
        By default we will consider them top-level packages\n")

    connectionStringAirlineUserdbowner <- helper_getSetting("connectionStringAirlineUserdbowner")
    scope <- "private"
    packageName <- c("glue")

    cat("\nINFO: checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionStringAirlineUserdbowner, 1)

    #
    # remove old packages if any and verify they aren't there
    #
    cat("\nINFO: removing packages...\n")
    if (helper_remote.require( connectionStringAirlineUserdbowner, packageName) == TRUE)
    {
        sql_remove.packages( connectionStringAirlineUserdbowner, packageName, verbose = TRUE, scope = scope)
    }

    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, packageName, FALSE)

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
        helper_CreateExternalLibrary(connectionString = connectionStringAirlineUserdbowner, packageName = packageName, content = pkgContent)
    ))
    expect_true(!inherits(output, "try-error"))

    output <- try(capture.output(
        helper_callDummySPEES( connectionString = connectionStringAirlineUserdbowner)
    ))
    expect_true(!inherits(output, "try-error"))


    helper_checkPackageStatusFind( connectionStringAirlineUserdbowner, packageName, TRUE)

    # Enumerate packages and check that package is listed as top-level
    cat("\nTEST: enumerate packages and check that package is listed as top-level...\n")
    installedPkgs <- helper_tryCatchValue( sql_installed.packages(connectionString = connectionStringAirlineUserdbowner, fields=c("Package", "Attributes", "Scope")))

    expect_true(!inherits(installedPkgs$value, "try-error"))
    expect_equal(1, as.integer(installedPkgs$value['glue','Attributes']), msg=sprintf(" (expected package listed as top-level: pkg=%s)", packageName))

    # Remove package
    cat("\nTEST: remove package previously installed with CREATE EXTERNAL LIBRARY...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringAirlineUserdbowner, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, packageName, FALSE)
})
