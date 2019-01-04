# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(RODBC)
library(RODBCext)
library(sqlmlutils)
library(testthat)

context("Tests for sqlmlutils package management top level")

test_that("package top level install and remove", {
    #skip("temporaly_disabled")
    connectionStringAirlineUserdbowner <- helper_getSetting("connectionStringAirlineUserdbowner")
    scope <- "private"

    #
    # check package management is installed
    #
    cat("\nINFO: checking remote lib paths...\n")
    helper_checkSqlLibPaths(connectionStringAirlineUserdbowner, 1)
    packageName <- c("plyr")
    dependentPackageName <- "Rcpp"

    #
    # remove old packages if any and verify they aren't there
    #
    if (helper_remote.require( connectionStringAirlineUserdbowner, packageName) == TRUE)
    {
        cat("\nINFO: removing package:", packageName,"\n")
        sql_remove.packages( connectionStringAirlineUserdbowner, packageName, verbose = TRUE, scope = scope)
    }

    # Make sure dependent package does not exist on its own
    if (helper_remote.require(connectionStringAirlineUserdbowner, dependentPackageName) == TRUE)
    {
        cat("\nINFO: removing package:", dependentPackageName,"\n")
        sql_remove.packages( connectionStringAirlineUserdbowner, dependentPackageName, verbose = TRUE, scope = scope)
    }

    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, dependentPackageName, FALSE)

    #
    # install the package with its dependencies and check if its present
    #
    output <- try(capture.output(sql_install.packages( connectionStringAirlineUserdbowner, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, packageName, TRUE)
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, dependentPackageName, TRUE)

    # Promote dependent package to top most by explicit installation
    cat("\nTEST: promote dependent package to top most by explicit installation...\n")
    output <- try(capture.output(sql_install.packages( connectionStringAirlineUserdbowner, dependentPackageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully attributed packages on SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, dependentPackageName, TRUE)


    # Remove main package and make sure the dependent, now turned top most, does not being removed
    cat("\nTEST: remove main package and make sure the dependent, now turned top most, is not removed...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringAirlineUserdbowner, packageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, packageName, FALSE)
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, dependentPackageName, TRUE)

    # Make sure promoted dependent package can be removed
    cat("\nTEST: remove dependent package previously promoted to top most...\n")
    output <- try(capture.output(sql_remove.packages( connectionStringAirlineUserdbowner, dependentPackageName, verbose = TRUE, scope = scope)))
    expect_true(!inherits(output, "try-error"))
    expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    helper_checkPackageStatusRequire( connectionStringAirlineUserdbowner, dependentPackageName, FALSE)
})
