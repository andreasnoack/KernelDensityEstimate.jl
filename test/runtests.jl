using KernelDensityEstimate
using Base.Test
# include("BallTree01.jl")
# include("BallTreeDensity01.jl")
# include("KDE01.jl")
# include("DualTree01.jl")

# type BallTree
#   dims::Int64                     # dimension of data
#   num_points::Int64               # of points
#   centers::Array{Float64,1}       # ball centers, dims numbers per ball
#   ranges::Array{Float64,1}        # bounding box ranges, dims per ball, dist from center to one side
#   weights::Array{Float64,1}       # total weight in each ball
#
#   left_child::Array{Int64,1}
#   right_child::Array{Int64,1}     # left, right children; no parent indices
#   lowest_leaf::Array{Int64,1}
#   highest_leaf::Array{Int64,1}    # lower & upper leaf indices for each ball
#   permutation::Array{Int64,1}     # point's position in the original data
#
#   next::Int64                     # internal var for placing the non-leaf nodes
#
#   swapHandle::Function
#   calcStatsHandle::Function
#   data
# end
# type BallTreeDensity
#   bt::BallTree
#
#   KernelType
#   multibandwidth::Int64               # flag: is bandwidth uniform?
#
#   means::Array{Float64,1}                  # Weighted mean of points from this level down
#   bandwidth::Array{Float64,1}              # Variance or other multiscale bandwidth
#   bandwidthMin::Array{Float64,1}
#   bandwidthMax::Array{Float64,1}           # Bounds on BW in non-uniform case
#
#   calcStatsHandle::Function
#   swapHandle::Function
# end

# parse the output from matlab process
function parseMatPrintKDE(filename::ASCIIString)
  fid = open(filename,"r")
  dict = Dict{ASCIIString, Array{Float64,1}}()
  for line in eachline(fid)
    twos = split(split(line,"\n")[1],"=")
    s = (split(split(twos[2],"[")[2],"]")[1])
    dict[twos[1]] = vec(readdlm(IOBuffer(s),','))
  end
  close(fid)
  return dict
end

function constructBTD(dict::Dict{ASCIIString, Array{Float64,1}})
  refbt = BallTree(dict["dims"][1],dict["num_points"][1],
  dict["centers"], #
  dict["ranges"], # =
  dict["weights"], #
  round(Int64,dict["left_child"]), # =
  round(Int64,dict["right_child"]), # =
  round(Int64,dict["lowest_leaf"]), # =
  round(Int64,dict["highest_leaf"]), # =
  round(Int64,dict["permutation"]), # =
  0, +, +, Union{} )

  refbtd = BallTreeDensity(refbt, Union{}, 0,
  dict["means"], # =
  dict["bandwidth"], # =
  dict["bwMin"],
  dict["bwMax"],
  +, +)
  return refbtd
end

function testSubtract(b1::BallTreeDensity, b2::BallTreeDensity, tol=1e-10)
    #@show b1.bt.dims, b2.bt.dims, b1.bt.num_points, b2.bt.num_points
    if (b1.bt.dims - b2.bt.dims) != 0 || (b1.bt.num_points - b2.bt.num_points) != 0
        error("testSubtract -- b1 and b2 are not the same size.")
    end
    function testDiffs(a1::Array{Float64},a2::Array{Float64}; tol=1e-10, name="")
        n = norm(a1 - a2)
        if n > tol
          @show name, n
          error("testSubtract -- b1 and b2 are not the same.")
        end
        nothing
    end
    function testInds(a1::Array{Int64},a2::Array{Int64})
        for i in 1:length(a1)
            res = 0
            if (a1[i] < 0)
                res = (a2[i]+1)
            else
                res = (a1[i]+1-a2[i])
            end
            if res != 0
              error("testSubtract -- b1 and b2 have different indices.")
            end
        end
        nothing
    end
    testDiffs(b1.bt.centers, b2.bt.centers, name="centers", tol=tol)
    testDiffs(b1.bt.ranges, b2.bt.ranges, name="ranges", tol=tol)
    testDiffs(b1.bt.weights, b2.bt.weights, name="weights", tol=tol)
    testInds(b1.bt.left_child, b2.bt.left_child)
    testInds(b1.bt.right_child, b2.bt.right_child)
    testInds(b1.bt.lowest_leaf, b2.bt.lowest_leaf)
    testInds(b1.bt.highest_leaf, b2.bt.highest_leaf)
    testInds(b1.bt.permutation[(b1.bt.num_points+1):end], b2.bt.permutation[(b2.bt.num_points+1):end])
    testDiffs(b1.means, b2.means, name="means", tol=tol)
    testDiffs(b1.bandwidth, b2.bandwidth, tol=tol)
    testDiffs(b1.bandwidthMin, b2.bandwidthMin, tol=tol)
    testDiffs(b1.bandwidthMax, b2.bandwidthMax, tol=tol)
    println("Success")
    true
end


function UnitTest1D01()
  print("Running UnitTest1D01...")
  p = kde!([.1,.45,.55,3.8],[0.08])

  d = parseMatPrintKDE("testdata/test1DResult.txt")
  refbtd = constructBTD(d)

  # printBallTree(p)
  testSubtract(refbtd, p, 1e-5)
end


function UnitTest1Dlcv01()
  print("Running UnitTest1Dlcv01...")
  x = vec(readdlm("testdata/test1Dlcv100.txt")')
  p = kde!(x,"lcv")

  d = parseMatPrintKDE("testdata/test1Dlcv100Result.txt")
  refbtd = constructBTD(d)

  # printBallTree(p)
  testSubtract(refbtd, p, 1e-4)
end

function UnitTest2D01()
  print("Running UnitTest2D01...")
  pts = [[0.5172, 0.7169, 0.4049]';
         [0.0312, 1.0094, 2.0204]']
  p = kde!(pts,[0.1])

  d = parseMatPrintKDE("testdata/test2DResult.txt")
  refbtd = constructBTD(d)

  # printBallTree(p)
  testSubtract(refbtd, p, 1e-5)
end

function UnitTest2Dlcv01()
  print("Running UnitTest2Dlcv01...")
  x = readdlm("testdata/test2Dlcv100.txt")'
  p = kde!(x,"lcv")

  d = parseMatPrintKDE("testdata/test2Dlcv100Result.txt")
  refbtd = constructBTD(d)

  # printBallTree(p)
  testSubtract(refbtd, p, 1e-4)
end

function UnitTest2Dvar01()
  print("Running UnitTest2Dvar01...")
  pts = [[0.5172, 7.169, 4.049]';
         [0.0312, 10.0094, -2.0204]']
  p=kde!(pts,[0.1; 1.0]);
  d = parseMatPrintKDE("testdata/test2DvarResult.txt")
  refbtd = constructBTD(d)

  # printBallTree(p)
  testSubtract(refbtd, p, 1e-4)
end

function UnitTest2Dvarlcv01()
  print("Running UnitTest2Dvarlcv01...")
  x = readdlm("testdata/test2Dvarlcv100.txt")'
  p = kde!(x,"lcv")

  d = parseMatPrintKDE("testdata/test2Dvarlcv100Result.txt")
  refbtd = constructBTD(d)

  # printBallTree(p)
  testSubtract(refbtd, p, 2e-3)
end

function testProds(;D=3,M=6,N=100,n=100, MCMC=5)
  P = BallTreeDensity[];
  [push!(P, kde!(randn(D,N))) for i in 1:M];
  dummy = kde!(rand(D,n),[1.0]);
  pGM, = prodAppxMSGibbsS(dummy, P, Union{}, Union{}, MCMC);
  sum(pGM)<1e-14 ? error("testProds -- prodAppxMSGibbsS, nothing in pGM, len $(length(P))") : nothing
  norm(Base.mean(pGM,2)) < 0.2
end

global pass=false
try
  UnitTest1D01()
  UnitTest1Dlcv01()
  UnitTest2D01()
  #UnitTest2Dlcv01()
  #UnitTest2Dvar01()
  #UnitTest2Dvarlcv01()
  global pass=true
catch
  global pass=false
end
@test pass
