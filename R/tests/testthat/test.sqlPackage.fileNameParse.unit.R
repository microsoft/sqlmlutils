# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(testthat)

context("Tests for sqlmlutils package management file path parsing helpers")

#
# A package name "should contain only (ASCII) letters, numbers and dot, have at least two
# characters and start with a letter and not end in a dot.
# Source: https://cran.r-project.org/doc/manuals/r-devel/R-exts.html#The-DESCRIPTION-file
# Consequentially, this test ensures that the parsed package name are the characters
# that appear before the first underscore (_)
#
test_that("getPackageNameFromFilePath outputs correct package name", {
    expect_equal(sqlmlutils:::getPackageNameFromFilePath(c('C:\\packages\\binaries\\data.table_1.14.6.zip')), 'data.table')
    expect_equal(sqlmlutils:::getPackageNameFromFilePath(c('C:\\packages\\binaries\\sqlmlutils_1.2.0.zip')), 'sqlmlutils')
    expect_equal(sqlmlutils:::getPackageNameFromFilePath(c('C:\\packages\\binaries\\mypackage_metadata_1.14.6.zip')), 'mypackage')
    expect_equal(sqlmlutils:::getPackageNameFromFilePath(c('C:\\packages\\binaries\\st_1.2.7.zip')), 'st')
})

#
# Tests that checking for file existance on invalid filepaths properly fails.
#
test_that("areValidFilesPaths fails when files do not exist", {
    # Using 1 as a default value, functions under test don't use the value
    # for any calculations
    topMostPackageFlagAttribute <- 1

    # Generate list of sample file paths that would be provided by a user to sql_install.packages()
    fileList <- c('C:\\packages\\binaries\\data.table_1.14.6.zip')
    fileList <- append(fileList, c('C:\\packages\\binaries\\sqlmlutils_1.2.0.zip'))
    fileList <- append(fileList, c('C:\\packages\\binaries\\st_1.2.7.zip'))

    # As this is a unit test, the sample files in fileList do not actually exist
    expect_error(sqlmlutils:::areValidFilesPaths(pkgs = fileList))
})
