# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(testthat)
context("Tests to check logins")

test_that("Test DBO",
{
    hodbc <- sqlmlutils:::connectToServer(helper_getSetting("connectionStringDBO"))

    expect_false(is.null(hodbc))
    on.exit(dbDisconnect(hodbc), add = TRUE)
})

test_that("Test AirlineUserdbowner",
{
    hodbc <- sqlmlutils:::connectToServer(helper_getSetting("connectionStringAirlineUserdbowner"))

    expect_false(is.null(hodbc))
    on.exit(dbDisconnect(hodbc), add = TRUE)
})

test_that("Test AirlineUser",
{
    hodbc <- sqlmlutils:::connectToServer(helper_getSetting("connectionStringAirlineUser"))

    expect_false(is.null(hodbc))
    on.exit(dbDisconnect(hodbc), add = TRUE)
})
