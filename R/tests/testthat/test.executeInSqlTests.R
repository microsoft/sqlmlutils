# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

library(testthat)
context("executeInSQL tests")

TestArgs <- options("TestArgs")$TestArgs
connection <- TestArgs$connectionString
scriptDir <- TestArgs$scriptDirectory

test_that("Test with named args", {
    funcWithArgs <- function(arg1, arg2){
        print(arg1)
        return(arg2)
    }
    expect_output(
        expect_equal(
            executeFunctionInSQL(connection, funcWithArgs, arg1="blah1", arg2="blah2"),
            "blah2"),
        "blah1"
    )
})

test_that("Test ordered arguments", {
    funcNum <- function(arg1, arg2){
        stopifnot(typeof(arg1) == "integer")
        stopifnot(typeof(arg2) == "double")
        return(arg1 / arg2)
    }
    expect_error(executeFunctionInSQL(connection, funcNum, 2))
    expect_equal(executeFunctionInSQL(connection, funcNum, as.integer(2), 3), 2/3)
    expect_equal(executeFunctionInSQL(connection, funcNum, as.integer(3), 2), 3/2)
})

test_that("Test Return", {
    myReturnVal <- function(){
        return("returned!")
    }

    val = executeFunctionInSQL(connection, myReturnVal)
    expect_equal(val, myReturnVal())
})

test_that("Test Warning", {
    printWarning <- function(){
        warning("testWarning")
        print("Hello, this returned")
    }
    expect_warning(
        expect_output(executeFunctionInSQL(connection, printWarning),
                      "Hello, this returned"),
        "testWarning")

})

test_that("Passing in a user defined function", {
    func1 <- function(){
        func2 <- function() {
            return("Success")
        }
        return(func2())
    }

    expect_equal(executeFunctionInSQL(connection, func=func1), "Success")
})

test_that("Returning a function object", {
    func2 <- function() {
        return("Success")
    }
    func1 <- function(){
        func2 <- function() {
            return("Success")
        }
        return(func2)
    }

    expect_equal(executeFunctionInSQL(connection, func=func1), func2)
})

test_that("Calling an object in the environment", {
    skip("This doesn't work right now because we don't pass the whole environment")

    func2 <- function() {
        return("Success")
    }
    func1 <- function(){
        return(func2)
    }

    expect_equal(executeFunctionInSQL(connection, func=func1), func2)
})

test_that("No Parameters test", {
    noReturn <- function() {
    }
    result = executeFunctionInSQL(connection, noReturn)
    expect_null(result)
})

test_that("Print, Warning, Return test", {

    returnString <- function() {
        print("hello")
        warning("uh oh")
        return("bar")
    }
    expect_warning(expect_output(result <- executeFunctionInSQL(connection, returnString), "hello"), "uh oh")

    expect_equal(result , "bar")
    
})

test_that("Print, Warning, Return test, with args", {

    returnVector <- function(a,b) {
        print("print")
        warning("uh oh")
        return(c(a,b))
    }
    expect_warning(expect_output(result <- executeFunctionInSQL(connection, returnVector, "foo", "bar"), "print"), "uh oh")

    expect_equal(result , c("foo","bar"))
})

test_that("Print, Warning, Error test", {
    testError <- function() {
        print("print")
        warning("warning")
        stop("ERROR")
    }
    expect_error(
        expect_warning(
            expect_output(
                result <- executeFunctionInSQL(connection, testError),
                "print"),
            "warning"),
        "ERROR")
})

test_that("Return a DataFrame", {

    returnDF <- function(a, b) {
        return(data.frame(x = c(foo=a,bar=b)))
    }
    result <- executeFunctionInSQL(connection, returnDF, "foo", 2)
    expect_equal(result, data.frame(x = c(foo="foo",bar=2)))
})

test_that("Return an input DataFrame", {
    useInputDataSet <- function(in_df) {
        return(in_df)
    }
    result = executeFunctionInSQL(connection, useInputDataSet, inputDataQuery = "SELECT TOP 5 * FROM airline5000")
    expect_equal(nrow(result), 5)
    expect_equal(ncol(result), 30)

    useInputDataSet2 <- function(in_df, t1) {
        return(list(in_df, t1=t1))
    }
    result = executeFunctionInSQL(connection, useInputDataSet2, t1=5, inputDataQuery = "SELECT TOP 5 * FROM airline5000")
    expect_equal(result$t1, 5)
    expect_equal(ncol(result[[1]]), 30)

})

test_that("Variable test", {

    printString <- function(str) {
        print(str)
    }
    expect_output(executeFunctionInSQL(connection, printString, str="Hello"), "Hello")
    test <- "World"
    expect_output(executeFunctionInSQL(connection, printString, str=test), test)
})

test_that("Query test", {
    res <- executeSQLQuery(connectionString = connection, sqlQuery = "SELECT TOP 5 * FROM airline5000")
    expect_equal(nrow(res), 5)
    expect_equal(ncol(res), 30)
})

test_that("Script test", {
    script <- file.path(scriptDir, 'script.txt')

    expect_warning(
        expect_output(
                res <- executeScriptInSQL(connectionString=connection, script=script, inputDataQuery = "SELECT TOP 5 * FROM airline5000"),
            "Hello"),
        "WARNING")
    expect_equal(nrow(res), 5)
    expect_equal(ncol(res), 30)

    script2 <- file.path(scriptDir, 'script2.txt')


    expect_output(res <- executeScriptInSQL(connection, script2), "Script path exists")
    expect_equal(res, 33)

    expect_error(res <- executeScriptInSQL(connection, "non-existent-script.txt"), regexp = "Script path doesn't exist")

})
