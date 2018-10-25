# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(sqlmlutils)
library(methods)
library(testthat)

options(keep.source = TRUE)
Sys.setenv(TZ='GMT')

print(Sys.getenv())

Driver <- Sys.getenv("DRIVER")
if (Driver == '') Driver <- "SQL Server"

Server <- Sys.getenv("SERVER")
if (Server == '') Server <- "."

Database <- Sys.getenv("DATABASE")
if (Database == '') Database <- "AirlineTestDB"

Uid <- Sys.getenv("USER")
Pwd <- Sys.getenv("PASSWORD")
if(Uid == '') Uid = NULL
if(Pwd == '') Pwd = NULL

cnnstr <- connectionInfo(driver=Driver, server=Server, database=Database, uid=Uid, pwd=Pwd)
print(cnnstr)

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
