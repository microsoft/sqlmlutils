# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(testthat)

context("Tests for sqlmlutils package management scope")

test_that("dbo cannot install package into private scope",
{
    # There is an issue running this test in github actions CI environment.
    # We will need to investigate why it failed. For now, we will disable the test in CI.
    skip_on_ci()

    skip_if(helper_isServerLinux(), "Linux tests do not have support for Trusted user." )

    connectionStringDBO <- helper_getSetting("connectionStringDBO")
    packageName <- c("xtable")
    
    tryCatch({    
        output <- try(capture.output(sql_install.packages(connectionString = connectionStringDBO, packageName, verbose = TRUE, scope="private")))
        expect_true(inherits(output, "try-error"))
        expect_equal(1, sum(grepl("Permission denied for installing packages on SQL server for current user", output)))
        helper_checkPackageStatusRequire( connectionString = connectionStringDBO,  packageName, FALSE)
    }, finally={
        helper_cleanAllExternalLibraries(connectionStringDBO)
    })
})

test_that( "package install and remove, PUBLIC scope",
{
    skip_if(helper_isServerLinux(), "Linux tests do not have support for Trusted user." )

    connectionStringDBO <- helper_getSetting("connectionStringDBO")

    tryCatch({
        packageName <- c("A3")
    
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
    }, finally={
        helper_cleanAllExternalLibraries(connectionStringDBO)
    })
})

test_that( "package install and remove, PRIVATE scope",
{
    packageName <- c("A3")

    #
    # --- AirlineUser user install and remove tests ---
    #
    connectionStringAirlineUser <- helper_getSetting("connectionStringAirlineUser")

    tryCatch({
        #
        # remove packages from private scope
        #
        cat("TEST: AirlineUser: removing packages from private scope...\n")
        try(sql_remove.packages( connectionStringAirlineUser, packageName, scope = 'private', verbose = TRUE))
        helper_checkPackageStatusFind(connectionStringAirlineUser, packageName, FALSE)
    
        #
        # install package in private scope
        #
        cat("TEST: AirlineUser: installing packages in private scope...\n")
        sql_install.packages( connectionStringAirlineUser, packageName, scope = 'private', verbose = TRUE)
        helper_checkPackageStatusFind(connectionStringAirlineUser, packageName, TRUE)
    
        #
        # uninstall package in private scope
        #
        cat("TEST: AirlineUser: removing packages from private scope...\n")
        sql_remove.packages( connectionStringAirlineUser, packageName, scope = 'private', verbose = TRUE)
        helper_checkPackageStatusFind(connectionStringAirlineUser, packageName, FALSE)
    }, finally={
        helper_cleanAllExternalLibraries(connectionStringAirlineUser)
    })
})
