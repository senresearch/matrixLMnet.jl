"""
    Mlmnet_cv(MLMNets, lambdas, data, rowFolds, colFolds)

Type for storing the results of running cross-validation for `mlmnet`

"""
mutable struct Mlmnet_cv 
    
    # Mlmnet objects
    MLMNets::Array{Mlmnet, 1} 
    # Lambda penalties
    lambdas::Array{Float64,1} 
    
    # Response and predictor matrices
    data::RawData 
    # Row folds 
    rowFolds::Array{Array,1} 
    # Column folds
    colFolds::Array{Array,1} 
    
    # These will be generated and should not be supplied as input to the 
    # constructor.
    # Test MSE for each of the CV folds for each lambda
    mse::Array{Float64, 2} 
    # Proportion of zero interaction coefficients for each of the CV folds 
    # for each lambda
    propZero::Array{Float64, 2} 
    
    Mlmnet_cv(MLMNets, lambdas, data, rowFolds, colFolds, dig) = 
        new(MLMNets, lambdas, data, rowFolds, colFolds, 
            calc_mse(MLMNets, data, lambdas, rowFolds, colFolds), 
            calc_prop_zero(MLMNets, lambdas; dig=dig))
end


"""
    mlmnet_cv(fun, data, lambdas, rowFolds, colFolds; 
              isXIntercept, isZIntercept, isXReg, isZReg, 
              isXInterceptReg, isZInterceptReg, isStandardize, isVerbose, 
              stepsize, setStepsize, dig, funArgs...)

Performs cross-validation for `mlmnet` using row and column folds from user 
input. 

# Arguments

- fun = function that applies an L1-penalty estimate method
- data = RawData object
- lambdas = 1d array of floats consisting of lambda penalties in descending 
  order. If they are not in descending order, they will be sorted. 
- rowFolds = 1d array of arrays (one array for each fold), each containing 
  the indices for a row fold; must be same length as colFolds. Can be 
  generated with a call to `make_folds`, which is based on `Kfold` from the 
  MLBase package. 
- colFolds = 1d array of arrays (one array for each fold), each containing 
  the indices for a column fold; must be same length as rowFolds. Can be 
  generated with a call to `make_folds`, which is based on `Kfold` from the 
  MLBase package

# Keyword arguments

- isXIntercept = boolean flag indicating whether or not to include an `X` 
  intercept (row main effects). Defaults to `true`. 
- isZIntercept = boolean flag indicating whether or not to include a `Z` 
  intercept (column main effects). Defaults to `true`.
- isXReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `X` (row) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `X` effects (equivalent to `data.p`). 
- isZReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `Z` (column) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `Z` effects (equivalent to `data.q`). 
- isXInterceptReg = boolean flag indicating whether or not to regularize the 
  `X` intercept Defaults to `false`. 
- isZInterceptReg = boolean flag indicating whether or not to regularize the 
  `Z` intercept. Defaults to `false`. 
- isStandardize = boolean flag indicating if the columns of `X` and `Z` 
  should be standardized (to mean 0, standard deviation 1). Defaults to `true`.
- isVerbose = boolean flag indicating whether or not to print messages.  
  Defaults to `true`. 
- stepsize = float; step size for updates (irrelevant for coordinate 
  descent and when `setStepsize` is set to `true` for `ista!` and `fista!`). 
  Defaults to `0.01`. 
- setStepsize = boolean flag indicating whether the fixed step size should be 
  calculated (for `ista!` and `fista!`). Defaults to `true`.
- dig = integer; digits of precision for zero coefficients. Defaults to 12. 
- funArgs = variable keyword arguments to be passed into `fun`

# Value

An Mlmnet_cv object. 

# Some notes

This is the base `mlmnet_cv` function that all other variants call. Folds 
are computed in parallel when possible. 

"""
function mlmnet_cv(fun::Function, data::RawData, 
                   lambdas::AbstractArray{Float64,1}, 
                   rowFolds::Array{Array{Int64,1},1}, 
                   colFolds::Array{Array{Int64,1},1}; 
                   isXIntercept::Bool=true, isZIntercept::Bool=true, 
                   isXReg::BitArray{1}=trues(size(get_X(data),2)), 
                   isZReg::BitArray{1}=trues(size(get_Z(data),2)), 
                   isXInterceptReg::Bool=false, isZInterceptReg::Bool=false, 
                   isStandardize::Bool=true, isVerbose::Bool=true, 
                   stepsize::Float64=0.01, setStepsize::Bool=true, 
                   dig::Int64=12, funArgs...)
    
    # Number of folds
    nFolds = length(rowFolds)
    # Ensure that the number of row folds is the same as the number of column 
    # folds
    if nFolds != length(colFolds)
        error("Number of row folds must equal number of column folds. ")
    else
        println_verbose(string("Performing ", nFolds, 
                               "-fold cross validation."), isVerbose) 
    end

    # Generate list of RawData objects that hold out each of the folds
    dataFolds = Array{RawData}(undef, nFolds)
    for i in 1:nFolds
        dataFolds[i] = RawData(Response(get_Y(data)[rowFolds[i], 
                                                    colFolds[i]]), 
                               Predictors(get_X(data)[rowFolds[i],:], 
                                          get_Z(data)[colFolds[i],:],  
                                          data.predictors.isXIntercept, 
                                          data.predictors.isZIntercept))
    end
    
    # Run mlmnet on each RawData object, in parallel when possible
    MLMNets = Distributed.pmap(data -> mlmnet(fun, data, lambdas; 
                                              isXIntercept=isXIntercept, 
                                              isZIntercept=isZIntercept, 
                                              isXReg=isXReg, isZReg=isZReg, 
                                              isXInterceptReg=isXInterceptReg, 
                                              isZInterceptReg=isZInterceptReg, 
                                              isStandardize=isStandardize, 
                                              isVerbose=isVerbose, 
                                              stepsize=stepsize, 
                                              setStepsize=setStepsize, 
                                              funArgs...), dataFolds)
    
    return Mlmnet_cv(MLMNets, lambdas, data, rowFolds, colFolds, dig)
end


"""
    mlmnet_cv(fun, data, lambdas, rowFolds, nColFolds; 
              isXIntercept, isZIntercept, isXReg, isZReg, 
              isXInterceptReg, isZInterceptReg, isStandardize, isVerbose, 
              stepsize, setStepsize, dig, funArgs...)

Performs cross-validation for `mlmnet` using row folds from user input and 
non-overlapping column folds randomly generated using a call to `make_folds`. 
Calls the base `mlmnet_cv` function. 

# Arguments

- fun = function that applies an L1-penalty estimate method
- data = RawData object
- lambdas = 1d array of floats consisting of lambda penalties in descending 
  order. If they are not in descending order, they will be sorted. 
- rowFolds = 1d array of arrays (one array for each fold), each containing 
  the indices for a row fold. Can be generated with a call to `make_folds`, 
  which is based on `Kfold` from the MLBase package. 
- nColFolds = integer corresponding to the number of column folds to randomly 
  generate. Can be either `length(rowFolds)` or `1` (to use all columns in 
  every fold). 

# Keyword arguments

- isXIntercept = boolean flag indicating whether or not to include an `X` 
  intercept (row main effects). Defaults to `true`. 
- isZIntercept = boolean flag indicating whether or not to include a `Z` 
  intercept (column main effects). Defaults to `true`.
- isXReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `X` (row) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `X` effects (equivalent to `data.p`). 
- isZReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `Z` (column) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `Z` effects (equivalent to `data.q`). 
- isXInterceptReg = boolean flag indicating whether or not to regularize the 
  `X` intercept Defaults to `false`. 
- isZInterceptReg = boolean flag indicating whether or not to regularize the 
  `Z` intercept. Defaults to `false`. 
- isStandardize = boolean flag indicating if the columns of `X` and `Z` 
  should be standardized (to mean 0, standard deviation 1). Defaults to `true`.
- isVerbose = boolean flag indicating whether or not to print messages.  
  Defaults to `true`. 
- stepsize = float; step size for updates (irrelevant for coordinate 
  descent and when `setStepsize` is set to `true` for `ista!` and `fista!`). 
  Defaults to `0.01`. 
- setStepsize = boolean flag indicating whether the fixed step size should be 
  calculated (for `ista!` and `fista!`). Defaults to `true`.
- dig = integer; digits of precision for zero coefficients. Defaults to 12. 
- funArgs = variable keyword arguments to be passed into `fun`

# Value

An Mlmnet_cv object. 

# Some notes

Folds are computed in parallel when possible. 

"""
function mlmnet_cv(fun::Function, data::RawData, 
                   lambdas::AbstractArray{Float64,1}, 
                   rowFolds::Array{Array{Int64,1},1}, nColFolds::Int64; 
                   isXIntercept::Bool=true, isZIntercept::Bool=true, 
                   isXReg::BitArray{1}=trues(size(get_X(data),2)), 
                   isZReg::BitArray{1}=trues(size(get_Z(data),2)), 
                   isXInterceptReg::Bool=false, isZInterceptReg::Bool=false, 
                   isStandardize::Bool=true, isVerbose::Bool=true, 
                   stepsize::Float64=0.01, setStepsize::Bool=true, 
                   dig::Int64=12, funArgs...)
    
    # Generate random column folds
    colFolds = make_folds(data.m, nColFolds, length(rowFolds))
    
    # Pass in user input row folds and randomly generated column folds to the 
    # base mlmnet_cv function
    mlmnet_cv(fun, data, lambdas, rowFolds, colFolds; 
              isXIntercept=isXIntercept, isZIntercept=isZIntercept, 
              isXReg=isXReg, isZReg=isZReg, 
              isXInterceptReg=isXInterceptReg, 
              isZInterceptReg=isZInterceptReg, 
              isVerbose=isVerbose, isStandardize=isStandardize, 
              stepsize=stepsize, setStepsize=setStepsize, dig=dig, funArgs...)
end


"""
    mlmnet_cv(fun, data, lambdas, nRowFolds, colFolds; 
              isXIntercept, isZIntercept, isXReg, isZReg, 
              isXInterceptReg, isZInterceptReg, isStandardize, isVerbose, 
              stepsize, setStepsize, dig, funArgs...)

Performs cross-validation for `mlmnet` using non-overlapping row folds 
randomly generated using a call to `make_folds` and column folds from user 
input. Calls the base `mlmnet_cv` function. 

# Arguments

- fun = function that applies an L1-penalty estimate method
- data = RawData object
- lambdas = 1d array of floats consisting of lambda penalties in descending 
  order. If they are not in descending order, they will be sorted. 
- nRowFolds = integer corresponding to the number of row folds to randomly 
  generate. Can be either `length(colFolds)` or `1` 
  (to use all rows in every fold). 
- colFolds = 1d array of arrays (one array for each fold), each containing 
  the indices for a column fold. Can be generated with a call to `make_folds`, 
  which is based on `Kfold` from the MLBase package. 

# Keyword arguments

- isXIntercept = boolean flag indicating whether or not to include an `X` 
  intercept (row main effects). Defaults to `true`. 
- isZIntercept = boolean flag indicating whether or not to include a `Z` 
  intercept (column main effects). Defaults to `true`.
- isXReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `X` (row) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `X` effects (equivalent to `data.p`). 
- isZReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `Z` (column) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `Z` effects (equivalent to `data.q`). 
- isXInterceptReg = boolean flag indicating whether or not to regularize the 
  `X` intercept Defaults to `false`. 
- isZInterceptReg = boolean flag indicating whether or not to regularize the 
  `Z` intercept. Defaults to `false`. 
- isStandardize = boolean flag indicating if the columns of `X` and `Z` 
  should be standardized (to mean 0, standard deviation 1). Defaults to `true`.
- isVerbose = boolean flag indicating whether or not to print messages.  
  Defaults to `true`. 
- stepsize = float; step size for updates (irrelevant for coordinate 
  descent and when `setStepsize` is set to `true` for `ista!` and `fista!`). 
  Defaults to `0.01`. 
- setStepsize = boolean flag indicating whether the fixed step size should be 
  calculated (for `ista!` and `fista!`). Defaults to `true`.
- dig = integer; digits of precision for zero coefficients. Defaults to 12. 
- funArgs = variable keyword arguments to be passed into `fun`

# Value

An Mlmnet_cv object. 

# Some notes

Folds are computed in parallel when possible. 

"""
function mlmnet_cv(fun::Function, data::RawData, 
                   lambdas::AbstractArray{Float64,1}, 
                   nRowFolds::Int64, colFolds::Array{Array{Int64,1},1}; 
                   isXIntercept::Bool=true, isZIntercept::Bool=true, 
                   isXReg::BitArray{1}=trues(size(get_X(data),2)), 
                   isZReg::BitArray{1}=trues(size(get_Z(data),2)), 
                   isXInterceptReg::Bool=false, isZInterceptReg::Bool=false, 
                   isStandardize::Bool=true, isVerbose::Bool=true, 
                   stepsize::Float64=0.01, setStepsize::Bool=true, 
                   dig::Int64=12, funArgs...)
    
    # Generate random row folds
    rowFolds = make_folds(data.n, nRowFolds, length(colFolds))
    
    # Pass in randomly generated row folds and user input column folds to the 
    # base mlmnet_cv function
    mlmnet_cv(fun, data, lambdas, rowFolds, colFolds; 
              isXIntercept=isXIntercept, isZIntercept=isZIntercept, 
              isXReg=isXReg, isZReg=isZReg, 
              isXInterceptReg=isXInterceptReg, 
              isZInterceptReg=isZInterceptReg, 
              isVerbose=isVerbose, isStandardize=isStandardize, 
              stepsize=stepsize, setStepsize=setStepsize, dig=dig, funArgs...)
end


"""
    mlmnet_cv(fun, data, lambdas, nRowFolds, nColFolds; 
              isXIntercept, isZIntercept, isXReg, isZReg, 
              isXInterceptReg, isZInterceptReg, isStandardize, isVerbose, 
              stepsize, setStepsize, dig, funArgs...)

Performs cross-validation for `mlmnet` using non-overlapping row and column 
folds randomly generated using calls to `make_folds`. Calls the base 
`mlmnet_cv` function. 

# Arguments

- fun = function that applies an L1-penalty estimate method
- data = RawData object
- lambdas = 1d array of floats consisting of lambda penalties in descending 
  order. If they are not in descending order, they will be sorted. 
- nRowFolds = integer corresponding to the number of row folds to randomly 
  generate. Can be either equal to `nColFolds` or `1` 
  (to use all rows in every fold). 
- nColFolds = integer corresponding to the number of column folds to randomly 
  generate. Can be either equal to `nRowFolds` or `1` (to use all columns in 
  every fold). 

# Keyword arguments

- isXIntercept = boolean flag indicating whether or not to include an `X` 
  intercept (row main effects). Defaults to `true`. 
- isZIntercept = boolean flag indicating whether or not to include a `Z` 
  intercept (column main effects). Defaults to `true`.
- isXReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `X` (row) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `X` effects (equivalent to `data.p`). 
- isZReg = 1d array of bit flags indicating whether or not to regularize each 
  of the `Z` (column) effects. Defaults to 2d array of `true`s with length 
  equal to the number of `Z` effects (equivalent to `data.q`). 
- isXInterceptReg = boolean flag indicating whether or not to regularize the 
  `X` intercept Defaults to `false`. 
- isZInterceptReg = boolean flag indicating whether or not to regularize the 
  `Z` intercept. Defaults to `false`. 
- isStandardize = boolean flag indicating if the columns of `X` and `Z` 
  should be standardized (to mean 0, standard deviation 1). Defaults to `true`.
- isVerbose = boolean flag indicating whether or not to print messages.  
  Defaults to `true`. 
- stepsize = float; step size for updates (irrelevant for coordinate 
  descent and when `setStepsize` is set to `true` for `ista!` and `fista!`). 
  Defaults to `0.01`. 
- setStepsize = boolean flag indicating whether the fixed step size should be 
  calculated (for `ista!` and `fista!`). Defaults to `true`.
- dig = integer; digits of precision for zero coefficients. Defaults to 12. 
- funArgs = variable keyword arguments to be passed into `fun`

# Value

An Mlmnet_cv object. 

# Some notes

Folds are computed in parallel when possible. 

The default method for choosing the fixed step size for `fista!` or `ista!` 
is to use the reciprocal of the product of the maximum eigenvalues of 
`X*transpose(X)` and `Z*transpose(Z)`. This is computed when `fista!` or 
`ista!` is passed into the `fun` argument and `setStepsize` is set to `true`. 
If `setStepsize` is set to `false`, the value of the `stepsize` argument will 
be used as the fixed step size. Note that obtaining the eigenvalues when `X` 
and/or `Z` are very large may exceed computational limitations. 

Specifying a good starting step size (`stepsize`) and multiplying factor 
(`gamma`) when `fista_bt!` is passed into the `fun` argument can be difficult. 
Shrinking the step size too gradually can result in slow convergence. Doing so 
too quickly can cause the criterion to diverge. We have found that setting 
`stepsize` to 0.01 often works well in practice; choice of `gamma` appears to 
be less consequential. 

"""
function mlmnet_cv(fun::Function, data::RawData, lambdas::Array{Float64,1}, 
                   nRowFolds::Int64=10, nColFolds::Int64=10; 
                   isXIntercept::Bool=true, isZIntercept::Bool=true, 
                   isXReg::BitArray{1}=trues(size(get_X(data),2)), 
                   isZReg::BitArray{1}=trues(size(get_Z(data),2)), 
                   isXInterceptReg::Bool=false, isZInterceptReg::Bool=false, 
                   isStandardize::Bool=true, isVerbose::Bool=true, 
                   stepsize::Float64=0.01, setStepsize::Bool=true, 
                   dig::Int64=12, funArgs...)
	
    # Generate random row and column folds
    rowFolds = make_folds(data.n, nRowFolds, max(nRowFolds, nColFolds))
    colFolds = make_folds(data.m, nColFolds, max(nRowFolds, nColFolds))
    
    # Pass in randomly generated row and column folds to the base mlmnet_cv 
    # function
    mlmnet_cv(fun, data, lambdas, rowFolds, colFolds; 
              isXIntercept=isXIntercept, isZIntercept=isZIntercept, 
              isXReg=isXReg, isZReg=isZReg, 
              isXInterceptReg=isXInterceptReg, 
              isZInterceptReg=isZInterceptReg, 
              isVerbose=isVerbose, isStandardize=isStandardize, 
              stepsize=stepsize, setStepsize=setStepsize, dig=dig, funArgs...)
end
