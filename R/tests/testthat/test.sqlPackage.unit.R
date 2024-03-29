# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(testthat)

context("Tests for sqlmlutils package management unit")


test_that("checkOwner() catches bad owner parameter input",
{
    expect_equal(sqlmlutils:::checkOwner(NULL), NULL)
    expect_equal(sqlmlutils:::checkOwner(''), NULL)
    expect_equal(sqlmlutils:::checkOwner('AirlineUserdbowner'), NULL)
    expect_error(sqlmlutils:::checkOwner(c('a','b')))
    expect_error(sqlmlutils:::checkOwner(1))
    expect_equal(sqlmlutils:::checkOwner('01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567'), NULL)
    expect_error(sqlmlutils:::checkOwner('012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678'))
})

test_that("Package management ExtLib", {
    versionClass <- sqlmlutils:::sqlCheckPackageManagementVersion(connectionString = helper_getSetting("connectionStringDBO"))
    expect_equal(versionClass, "ExtLib")
})

test_that("GetServerVersion() Returns Server Version of R Successfully",{
    rversion <- sqlmlutils:::getserverVersion(connectionString = cnnstr, languageName = "R")
    # rversion value truncated, so R may be >= 3.5 (3.5.3) or >= 4.2
    expect_gte(as.double(rversion[['rversion']]), 3.5)
})
