def foo(t1, t2, t3):
    return str(t1)+str(t2)


param_str = foo(t1,t2,t3)

print("Testing output!")

# The double single quotes below are need for SPEES execution test.
data = {''Numbers'':[1, 2, 3, 4]}
OutputDataSet = DataFrame(data)
