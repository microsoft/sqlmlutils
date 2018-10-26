# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(testthat)
context("Stored Procedure tests")

TestArgs <- options('TestArgs')$TestArgs
connection <- TestArgs$connectionString
scriptDir <- TestArgs$scriptDirectory
sqlcmd_path <- TestArgs$sqlcmd

dropIfExists <- function(connectionString, name) {
    if(checkSproc(connectionString, name))
        invisible(capture.output(dropSproc(connectionString = connectionString, name = name)))
}

#
#Test an empty function (no inputs)
test_that("No Parameters test", {
    noParams <- function() {
        data.frame(hello = "world")
    }
    name = "noParams"

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromFunction(name, noParams, connectionString = connection))
    expect_true(checkSproc(name, connectionString = connection))

    expect_equal(as.character(executeSproc(connectionString = connection, name)[[1]]) , "world")

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})

#
#Test multiple input parameters
#("posixct", "numeric", "character", "integer", "logical", "raw", "dataframe")
test_that("Numeric, POSIXct, Character, Logical test", {
    inNumCharParams <- function(in1, in2, in3, in4) {
        data.frame(in1, in2,in3,in4)
    }

    #TODO: Time zone might not work
    x <- as.POSIXct(12345678, origin = "1960-01-01")#, tz= "GMT")

    inputParams <- list(in1="numeric", in2="posixct", in3="character", in4="logical")

    name = "inNumCharParams"

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromFunction(name, inNumCharParams, connectionString = connection, inputParams = inputParams))
    expect_true(checkSproc(name, connectionString = connection))

    res <- executeSproc(name, in1 = 1, in2 = x, in3 = "Hello", in4 = 1, connectionString = connection)

    expect_equal(res[[1]], 1)
    expect_equal(res[[2]], x)
    expect_equal(as.character(res[[3]]), "Hello")
    expect_equal(as.logical(res[[4]]), TRUE)

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})

#
#Test only an InputDataSet StoredProcedure
test_that("Simple InputDataSet test", {
    inData <- function(in_df) {
        in_df
    }

    inputParams <- list(in_df="dataframe")

    name = "inData"

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromFunction(name, inData, connectionString = connection, inputParams = inputParams))
    expect_true(checkSproc(name, connectionString = connection))

    res <- executeSproc(name, in_df = "SELECT TOP 10 * FROM airline5000", connectionString = connection)
    expect_equal(nrow(res), 10)
    expect_equal(ncol(res), 30)

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})


#
#Test InputDataSet with returned OutputDataSet
test_that("InputDataSet to OutputDataSet test", {
    inOutData <- function(in_df) {
        list(out_df = in_df)
    }

    inputParams <- list(in_df="dataframe")
    outputParams <- list(out_df="dataframe")

    name = "inOutData"

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromFunction(name, inOutData, connectionString = connection, inputParams = inputParams, outputParams = outputParams))
    expect_true(checkSproc(name, connectionString = connection))

    res <- executeSproc(name, in_df = "SELECT TOP 10 * FROM airline5000", connectionString = connection)
    expect_equal(nrow(res), 10)
    expect_equal(ncol(res), 30)

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})

#
#Test InputDataSet query with InputParameters
test_that("InputDataSet with InputParameter test", {
    inDataParams <- function(id, ip) {
        rbind(id,ip)
    }

    name = "inDataParams"

    inputParams = list(id = "DataFrame", ip = "numeric")

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromFunction(name, inDataParams, connectionString = connection, inputParams = inputParams))
    expect_true(checkSproc(name, connectionString = connection))

    res <- executeSproc(name, id = "SELECT TOP 10 * FROM airline5000", ip = 4, connectionString = connection)

    expect_equal(nrow(res), 11)
    expect_equal(ncol(res), 30)

    expect_error(executeSproc(name, "SELECT TOP 10 * FROM airline5000", ip = 4, connectionString = connection))

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})


#
#Test InputDataSet query with InputParameters with inputs out of order
test_that("InputDataSet with InputParameter test, out of order", {
    inDataParams <- function(id, ip, ip2) {
        rbind(id,ip)
    }

    name = "inDataParamsOoO"

    inputParams = list(ip = "numeric", id = "DATAFRAME", ip2 = "character")

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromFunction(name, inDataParams, connectionString = connection, inputParams = inputParams))
    expect_true(checkSproc(name, connectionString = connection))

    res <- executeSproc(name, ip2 = "Hello", ip = 4, id = "SELECT TOP 10 * FROM airline5000",  connectionString = connection)

    expect_equal(nrow(res), 11)
    expect_equal(ncol(res), 30)

    expect_error(executeSproc(name,ip = 4,  "SELECT TOP 10 * FROM airline5000", connectionString = connection))

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})


test_that("Stored Procedure with Scripts", {
    inputParams <- list(num1 = "numeric", num2 = "numeric", in_df = "dAtaFrame")
    outputParams <- list(out_df = "dataframe")

    name="script"

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromScript(
        connectionString = connection, name=name, file.path(scriptDir, "script3.R"), inputParams = inputParams, outputParams = outputParams))
    expect_true(checkSproc(connectionString = connection, name = name))

    retVal <- executeSproc(connectionString = connection, name, num1 = 3, num2 = 4, in_df = "select top 10 * from airline5000")

    expect_equal(nrow(retVal), 11)
    expect_equal(ncol(retVal), 30)

    dropIfExists(connectionString = connection, name = name)
    expect_false(checkSproc(connectionString = connection, name = name))
})

context("Sprocs with output params (TODO)")

# TODO: Output params test - execution doesn't work right now
test_that("Only OuputParams test", {
    outsFunc <- function(arg1) {
        list(res = paste0("Hello ", arg1, "!"))
    }

    name <- "outsFunc"
    inputParams <- list(arg1 = "character")
    outputParams <- list(res = "character")

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    capture.output(createSprocFromFunction(name, outsFunc, connectionString = connection, inputParams = inputParams, outputParams = outputParams))
    expect_true(checkSproc(name, connectionString = connection))


    #Use T-SQL to verify
    sql_str = "DECLARE @res nvarchar(max)  EXEC outsFunc @arg1_outer = N'T-SQL', @res_outer = @res OUTPUT SELECT @res as N'@res'"
    if(TestArgs$uid != "") {
        out <- system2(sqlcmd_path, c(  "-S", TestArgs$server,
                                        "-d", TestArgs$database, 
                                        "-Q", paste0('"', sql_str, '"'),
                                        "-U", TestArgs$uid,
                                        "-P", TestArgs$pwd), 
                                        stdout=TRUE)
    } else {
        out <- system2(sqlcmd_path, c(  "-S", TestArgs$server,
                                        "-d", TestArgs$database, 
                                        "-Q", paste0('"', sql_str, '"'),
                                        "-E"),
                                        stdout=TRUE)
    }
    expect_true(any(grepl("Hello T-SQL!", out)))
    #executeSproc(name, connectionString = connection, out1 = "Asd", out2 = "wqe")

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})


test_that("OutputDataSet and OuputParams test", {
    outDataParam <- function() {
        df = data.frame(hello = "world")
        list(df = df, out1 = "Hello", out2 = "World")
    }
    name = "outDataParam"
    
    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    outputParams <- list(df = "dataframe", out2 = "character", out1 = "character")

    createSprocFromFunction(name, outDataParam, connectionString = connection, outputParams = outputParams)
    expect_true(checkSproc(name, connectionString = connection))

    #Use T-SQL to verify
    sql_str = "DECLARE @out1 nvarchar(max),@out2 nvarchar(max)  EXEC outDataParam @out1_outer = @out1 OUTPUT, @out2_outer = @out2 OUTPUT SELECT @out1 as N'@out1'"
    if(TestArgs$uid != "") {
        out <- system2(sqlcmd_path, c(  "-S", TestArgs$server,
                                        "-d", TestArgs$database, 
                                        "-Q", paste0('"', sql_str, '"'),
                                        "-U", TestArgs$uid,
                                        "-P", TestArgs$pwd), 
                                        stdout=TRUE)
    } else {
        out <- system2(sqlcmd_path, c(  "-S", TestArgs$server,
                                        "-d", TestArgs$database, 
                                        "-Q", paste0('"', sql_str, '"'),
                                        "-E"),
                                        stdout=TRUE)
    }
    expect_true(any(grepl("Hello", out)))
    #res <- executeSproc(connectionString = connection, name)

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))
})

context("Sproc Negative Tests")

test_that("Bad input param types or usage", {
    badParam <- function(arg1) {
        return(arg1)
    }
    inputParams <- list(arg1 = "NotAType")

    expect_error(createSprocFromFunction(connection, "badParam", badParam, inputParams = inputParams))

    inputParams <- list(arg1 = "dataframe")

    name = "badInput"
    dropIfExists(connection, name)
    capture.output(createSprocFromFunction(connection, name, badParam, inputParams = inputParams))
    expect_true(checkSproc(connection, name))

    expect_error(expect_warning(executeSproc(connection, name, arg1=12314532)))
    res <- executeSproc(connection, name, arg1="SELECT TOP 5 * FROM airline5000")

    expect_equal(ncol(res), 30)
    expect_equal(nrow(res), 5)
    dropIfExists(connection, name)
})

test_that("Drop nonexistent sproc",{
    expect_false(checkSproc(connection, "NonexistentSproc"))
    expect_output(dropSproc(connection, "NonexistentSproc"), "Named procedure doesn't exist")
})

test_that("Create with bad name",{
    name = "'''asd''asd''asd"
    foo = function() {
        return(NULL)
    }
    expect_error(createSprocFromFunction(connection, name, foo))
})

test_that("mismatch input params", {
    func <- function(arg1, arg2) {
        return(arg1)
    }
    inputParams <- list(arg1 = "dataframe", arg3 = "numeric")

    dropIfExists(connection, "mismatch")
    expect_error(createSprocFromFunction(connection, "mismatch", func, inputParams = inputParams))

    inputParams <- list(arg1 = "dataframe", arg2 = "qwe", arg3 = "numeric")

    dropIfExists(connection, "mismatch")
    expect_error(createSprocFromFunction(connection, "mismatch", func, inputParams = inputParams))

})


test_that("Sproc with Bad Script Path", {
    name="bad_script_path"

    dropIfExists(name, connectionString = connection)
    expect_false(checkSproc(name, connectionString = connection))

    expect_error(createSprocFromScript(
        connectionString = connection, name=name, "bad_script_path.txt"))

})



