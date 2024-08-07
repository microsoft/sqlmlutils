# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(testthat)

context("Tests for sqlmlutils package management")

test_that( "successfull install and remove of package with special char in name that requires [] in t-sql",
{
    #
    # Set scope to public for trusted connection on Windows
    #
    scope <- if(!helper_isServerLinux()) "public" else "private"

    packageName <- c("abc.data")
    connectionStringDBO <- helper_getSetting("connectionStringDBO")

    tryCatch({
        #
        # Remove old packages if any and verify they aren't there
        #
        if (helper_remote.require( connectionStringDBO, packageName) == TRUE)
        {
            cat("\nINFO: removing package...\n")
            sql_remove.packages(connectionStringDBO, packageName, verbose = TRUE, scope = scope)
        }
    
        helper_checkPackageStatusRequire( connectionStringDBO, packageName, FALSE)
    
        #
        # Install single package (package has no dependencies)
        #
        output <- try(capture.output(sql_install.packages(connectionStringDBO, packageName, verbose = TRUE, scope = scope)))
        print(output)
        expect_true(!inherits(output, "try-error"))
        expect_equal(1, sum(grepl("Successfully installed packages on SQL server", output)))
    
        helper_checkPackageStatusRequire( connectionStringDBO, packageName, TRUE)
    
        #
        # Remove the installed package and check again they are gone
        #
        cat("\nINFO: removing package...\n")
        output <- try(capture.output(sql_remove.packages(connectionStringDBO, packageName, verbose = TRUE, scope = scope)))
        print(output)
        expect_true(!inherits(output, "try-error"))
        expect_equal(1, sum(grepl("Successfully removed packages from SQL server", output)))
    
        helper_checkPackageStatusRequire( connectionStringDBO, packageName, FALSE)
    }, finally={
        helper_cleanAllExternalLibraries(connectionStringDBO)
    })
})
