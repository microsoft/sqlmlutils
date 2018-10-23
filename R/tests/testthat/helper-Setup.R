# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(methods)
library(testthat)

options(keep.source = TRUE)
Sys.setenv(TZ='GMT')

print(Sys.getenv("TESTVAR"))

Server <- Sys.getenv("SERVER")
if (Server == '') Server <- "."

Database <- Sys.getenv("DATABASE")
if (Database == '') Database <- "AirlineTestDB"

cnnstr <- connectionInfo(server=Server, database=)

testthatDir <- getwd()
R_Root <- file.path(testthatDir, "../..")
scriptDirectory <- file.path(testthatDir, "scripts")

TestArgs <- list(
    # Compute context specifications
    gitRoot = R_Root,
    testDirectory = testthatDir,
    scriptDirectory = scriptDirectory,
    connectionString = cnnstr
)

options(TestArgs = TestArgs)
rm(TestArgs)
