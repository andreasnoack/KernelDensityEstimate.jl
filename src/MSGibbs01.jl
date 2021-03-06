type GbGlb
    # REMEMBER -- all multi-dim arrays are column-indexing!  [i,j] => [j*N+i]
    particles::Array{Float64,1} # [Ndim x Ndens]      // means of selected particles
    variance::Array{Float64,1}  # [Ndim x Ndens]      //   variance of selected particles
    p::Array{Float64,1}         # [Np]                // probability of ith kernel
    ind::Array{Int64,1}                    # current indexes of MCMC step
    Malmost::Array{Float64,1}
    Calmost::Array{Float64,1}   #[Ndim x 1]   // Means & Cov. of all indices but j^th
    # Random number callback
    randU::Array{Float64,1}     # [Npoints * Ndens * (Niter+1)] uniformly distrib'd random variables
    randN::Array{Float64,1}     # [Ndim * Npoints] normally distrib'd random variables
    Ndim::Int64
    Ndens::Int64
    Nlevels::Int64
    dNp::Int64
    newPoints::Array{Float64,1}
    newWeights::Array{Float64,1}
    newIndices::Array{Int64,1}
    trees::Array{BallTreeDensity,1}
    levelList::Array{Int64,2}
    levelListNew::Array{Int64,2}
    dNpts::Array{Int64,1}
    ruptr::Int64
    rnptr::Int64
end

function makeEmptyGbGlb()
   return GbGlb(zeros(0),
                zeros(0),
                zeros(0),
                zeros(Int64,0),
                zeros(0),
                zeros(0),
                zeros(0),
                zeros(0),
                0,0,0,0,
                zeros(0),
                zeros(0),
                ones(Int64,0),
                Vector{BallTreeDensity}(1),
                ones(Int64,1,0),
                ones(Int64,1,0),
                zeros(Int64,0),
                0, 0)
end


type MSCompOpt
  pT::Float64
  tmpC::Float64
  tmpM::Float64
end

function levelInit!(glb::GbGlb)
  for j in 1:glb.Ndens
    glb.dNpts[j] = 1
    glb.levelList[j,1] = root(glb.trees[j])
  end
end

# this is a weird function -- not tested at all at this point
function initIndices!(glb::GbGlb)
  count=1
  for j in 1:glb.Ndens
    dNp = glb.dNpts[j]
    zz=glb.levelList[j,1]
    z = 1
    while z <= dNp # ++z, used to be a for loop
      glb.p[z] = weight(glb.trees[j], zz);  # init by sampling from weights
        z+=1
        if z<=dNp zz=glb.levelList[j,z]; end
    end

    for z in 2:dNp
        glb.p[z] += glb.p[z-1];
    end
    zz=glb.levelList[j,1]
    z = 1
    while z <= (dNp-1)
      if (glb.randU[glb.ruptr] <= glb.p[z]) break; end #count
        z+=1
        if z<dNp zz=glb.levelList[j,z]; end
    end
    glb.ind[j] = zz;
    count+=1
    glb.ruptr += 1
  end
  #glb.randU = glb.randU[count:end]
end

function calcIndices!(glb::GbGlb)
  #println("oooooooooooooooooooooooooooooooo")
  @fastmath @inbounds begin
    for j in 1:glb.Ndens
      for z in 1:glb.Ndim
        #@show j, z, glb.ind[j]
        #@show mean(glb.trees[j],glb.ind[j])
        glb.particles[z+glb.Ndim*(j-1)] = mean(glb.trees[j],glb.ind[j], z)#[z];
        glb.variance[z+glb.Ndim*(j-1)]  = bw(glb.trees[j],glb.ind[j], z);
      end
    end
  end
  #println("pppppppppppppppppppppppppppppppp")
end

function samplePoint!(X::Array{Float64,1}, glb::GbGlb, frm::Int64)
  #counter = 1
  for j in 1:glb.Ndim
    mn=0.0; vn=0.0;
    for z in 1:glb.Ndens                             # Compute mean and variances of
      vn += 1.0/glb.variance[j+glb.Ndim*(z-1)]       #   product of selected particles
      #@show j, z, j+glb.Ndim*(z-1)
      #@show round([mn, glb.particles[j+glb.Ndim*(z-1)], glb.variance[j+glb.Ndim*(z-1)]],3)
      mn += glb.particles[j+glb.Ndim*(z-1)]/glb.variance[j+glb.Ndim*(z-1)]
    end
    vn = 1.0/vn; mn *= vn;
    glb.rnptr += 1
    X[j+frm] = mn + sqrt(vn) * glb.randN[glb.rnptr] #counter       # then draw a sample from it
    #counter+=1
  end
  #glb.randN = glb.randN[counter:end]   # TODO ugh
  return Union{}
end

function levelDown!(glb::GbGlb)
  for j in 1:glb.Ndens
    z = 1
    for y in 1:(glb.dNpts[j])
      #@show "left", y, j, left(glb.trees[j], glb.levelList[j,y])
      if validIndex(glb.trees[j], left(glb.trees[j], glb.levelList[j,y]))
        #@show "a", y, j, z, left(glb.trees[j], glb.levelList[j,y])
        glb.levelListNew[j,z] = left(glb.trees[j], glb.levelList[j,y])
        z+=1
      end
      #@show "right", y, j, right(glb.trees[j], glb.levelList[j,y])
      if validIndex(glb.trees[j], right(glb.trees[j], glb.levelList[j,y]))
        #@show "b", y, j, z, right(glb.trees[j], glb.levelList[j,y])
        glb.levelListNew[j,z] = right(glb.trees[j], glb.levelList[j,y]);
        z+=1
      end
      #@show "last", glb.ind[j], glb.levelList[j,y]
      if (glb.ind[j] == glb.levelList[j,y])                      # make sure ind points to
        #@show "c", y, j, z, glb.levelListNew[j,z-1]
        glb.ind[j] = glb.levelListNew[j,z-1]                     #  a child of the old ind
      end
    end
    glb.dNpts[j] = z-1
    #println("levelDown! -- glb.dNpts[j=$j]=$(glb.dNpts[j])")
  end
  tmp = glb.levelList                            # make new list the current
  glb.levelList = glb.levelListNew              #   list and recycle the old
  glb.levelListNew=tmp

  #println("A, levelList $(glb.levelList[1,:]), $(glb.levelList[2,:])")
  #println("A, levelListNew $(glb.levelListNew[1,:]), $(glb.levelListNew[2,:])")
  #println("A, ind $(glb.ind)")
end

function sampleIndices!(X::Array{Float64,1}, cmoi::MSCompOpt, glb::GbGlb, frm::Int64)#pT::Array{Float64,1}
  counter=1
  zz=0
  #z = 1
  for j in 1:glb.Ndens
    dNp = glb.dNpts[j]    #trees[j].Npts();
    cmoi.pT = 0.0

    ##z = 1
    zz=glb.levelList[j,1]#z
    #println("start zz=glb.levelList[$(j),$(z)]=$(zz)")
    for z in 1:dNp ##while <=
      #println("starting first z=$(z), dNp=$(dNp), zz=$(zz)")
      glb.p[z] = 0.0
      for i in 1:glb.Ndim
        tmp = X[i+frm] - mean(glb.trees[j], zz, i)#[i]
        glb.p[z] += (tmp*tmp) / bw(glb.trees[j], zz, i)#[i]
        glb.p[z] += Base.Math.JuliaLibm.log(bw(glb.trees[j], zz, i))
      end
      glb.p[z] = exp( -0.5 * glb.p[z] ) * weight(glb.trees[j], zz)
      cmoi.pT += glb.p[z]
      #println("end ++z zz=glb.levelList[$(j),$(z)]=$(zz)")
      ##z+=1
      #println("1 ++z=$(z)")
      zz = z<dNp ? glb.levelList[j,z+1] : zz
    end
    #println("after first zz=$(zz)")
    @simd for z in 1:dNp
        glb.p[z] /= cmoi.pT
    end
    @simd for z in 2:dNp
        glb.p[z] += glb.p[z-1]              # construct CDF and sample a
    end

    z=1
    zz=glb.levelList[j,z]
    #println("mid zz=glb.levelList[$(j),$(z)]=$(zz)")
    while z<=(dNp-1)
      #println("second zz=glb.levelList[$(j),$(z)]=$(zz)")
      if (glb.randU[glb.ruptr] <= glb.p[z]) # counter
        break;                              # new kernel from jth density
      end
      z+=1
      #println("2 ++z=$(z)")
      if z<=dNp
        zz=glb.levelList[j,z]
      else
        error("This should never happend due to -1 MSGibbs01.jl")
      end
    end
    glb.ind[j] = zz                          #  using those weights
    #println("sampleIndices -- glb.ind[j=$(j)]=$(glb.ind[j])")
    counter+=1
    glb.ruptr += 1
  end
  #glb.randU = glb.randU[counter:end]
  calcIndices!(glb);                         # recompute particles, variance
end

## SLOWEST PIECE OF THE COMPUTATION -- TODO
# easy PARALLELs overhead here is much slower, already tried -- rather search for BLAS optimizations...
function makeFasterSampleIndex!(j::Int64, cmo::MSCompOpt, glb::GbGlb)
  #pT::Array{Float64,1}
  cmo.tmpC = 0.0
  cmo.tmpM = 0.0

  zz=glb.levelList[j,1]
  #z=1
  for z in 1:(glb.dNpts[j])#dNp
    glb.p[z] = 0.0
    for i in 1:glb.Ndim
      cmo.tmpC = bw(glb.trees[j], zz, i) + glb.Calmost[i]
      cmo.tmpM = mean(glb.trees[j], zz, i) - glb.Malmost[i]
      glb.p[z] += abs2(cmo.tmpM)/cmo.tmpC + log(cmo.tmpC) # This is the slowest piece
    end
    glb.p[z] = exp( -0.5 * glb.p[z] ) * weight(glb.trees[j].bt, zz) # slowest piece
    z < glb.dNpts[j] ? zz = glb.levelList[j,(z+1)] : nothing
  end

  # incorrect! remember zz
  #@simd for z in 1:glb.dNpts[j]
  #  glb.p[z] = exp( -0.5 * glb.p[z] ) * weight(glb.trees[j], zz)
  #end
  nothing
end

function sampleIndex(j::Int64, cmo::MSCompOpt, glb::GbGlb)
#pT::Array{Float64,1}
  #dNp = glb.dNpts[j];  #trees[j].Npts();
  cmo.pT = 0.0

  # determine product of selected particles from all but jth density
  for i in 1:glb.Ndim
    iCalmost = 0.0; iMalmost = 0.0;
    for k in 1:glb.Ndens
      if (k!=j) iCalmost += 1.0/glb.variance[i+glb.Ndim*(k-1)]; end
      if (k!=j) iMalmost += glb.particles[i+glb.Ndim*(k-1)]/glb.variance[i+glb.Ndim*(k-1)]; end
    end
    glb.Calmost[i] = 1/iCalmost;
    glb.Malmost[i] = iMalmost * glb.Calmost[i];
  end

  makeFasterSampleIndex!(j, cmo, glb)

  @inbounds @simd for k in 1:glb.dNpts[j]
    cmo.pT += glb.p[k]
  end

  @inbounds @simd for z in 1:glb.dNpts[j]#dNp
    glb.p[z] /= cmo.pT            # normalize weights# normalize weights
  end
  @inbounds @simd for z in 2:glb.dNpts[j]#dNp
    glb.p[z] += glb.p[z-1]    # construct CDF and sample
  end
  zz=glb.levelList[j,1]
  z=1
  while z<=(glb.dNpts[j]-1)#dNp
    if (glb.randU[glb.ruptr] <= glb.p[z]) break;  end   #1  #   a new kernel from the jth
    z+=1
    if z<=glb.dNpts[j]#dNp
      zz=glb.levelList[j,z]
      #println("sampleIndex 2++z, , zz=glb.levelList[$(j),$(z)]=$(zz)")
    end
  end
  glb.ind[j] = zz;                                          #   density using these weights
  #glb.randU = glb.randU[2:end]
  glb.ruptr += 1

  for i in 1:glb.Ndim
    #@show round(glb.trees[j].means, 3)
    #@show i, j, glb.ind[j], mean(glb.trees[j], glb.ind[j])
    glb.particles[i+glb.Ndim*(j-1)] = mean(glb.trees[j], glb.ind[j], i)#[i]
    glb.variance[i+glb.Ndim*(j-1)]  = bw(glb.trees[j], glb.ind[j], i)#[i];
  end
end

function printGlbs(g::GbGlb, tag=Union{})
    if tag==Union{}
        println("=========================================================================")
    else
        println(string(tag,"================================================================"))
    end
    println("Ndim=$(g.Ndim), Ndens=$(g.Ndens), Nlevels=$(g.Nlevels), dNp=$(g.dNp), dNpts=$(g.dNpts)")
    @show g.ind
    @show round(g.particles,2)
    @show round(g.variance,2)
    @show round(g.p,2)
    @show round(g.Malmost,2)
    @show round(g.Calmost,2)
    @show g.levelList
    @show g.levelListNew
    @show round(g.newPoints,4)
    @show g.newIndices
end

function gibbs1(Ndens::Int64, trees::Array{BallTreeDensity,1},
                Np::Int64, Niter::Int64,
                pts::Array{Float64,1}, ind::Array{Int64,1},
                randU::Array{Float64,1}, randN::Array{Float64,1})

    glbs = makeEmptyGbGlb()
    glbs.Ndens = Ndens
    glbs.trees = trees
    glbs.newPoints = pts
    glbs.newIndices = ind
    glbs.randU = randU
    glbs.randN = randN
    glbs.Ndim = trees[1].bt.dims

    maxNp = 0                         # largest # of particles we deal with
    for tree in trees
        if (maxNp < Npts(tree))
            maxNp = Npts(tree)
        end
    end

    glbs.ind = ones(Int64,Ndens)
    glbs.p = zeros(maxNp)
    glbs.Malmost = zeros(glbs.Ndim)
    glbs.Calmost = zeros(glbs.Ndim)
    glbs.Nlevels = floor(Int64,((log(maxNp)/log(2))+1))
    glbs.particles = zeros(glbs.Ndim*Ndens)
    glbs.variance  = zeros(glbs.Ndim*Ndens)
    glbs.dNpts = zeros(Int64,Ndens)
    glbs.levelList = ones(Int64,Ndens,maxNp)
    glbs.levelListNew = ones(Int64,Ndens,maxNp)
    cmo = MSCompOpt(0.0, 0.0, 0.0)
    cmoi = MSCompOpt(0.0, 0.0, 0.0)

    ##@show glbs.ruptr, size(glbs.randU)
    for s in 1:Np   #   (for each sample:)
          #println("+++++++++++++++++++++++++++++NEW POINT+++++++++++++++++++++++++++++++++++++++")
        frm = ((s-1)*glbs.Ndim)

        levelInit!(glbs)
        initIndices!(glbs)
        calcIndices!(glbs)

        #printGlbs(glbs, string("s=",s-1.5))

        for l in 1:glbs.Nlevels
          samplePoint!(glbs.newPoints, glbs, frm)
          levelDown!(glbs);
          sampleIndices!(glbs.newPoints, cmoi, glbs, frm);

          #printGlbs(glbs, string("s=",s-1.5+.1*l))

          for i in 1:Niter         #   perform Gibbs sampling
            for j in 1:glbs.Ndens
              @fastmath @inbounds sampleIndex(j, cmo, glbs);
            end
          end
        end

        for j in 1:glbs.Ndens                       #/ save and
          glbs.newIndices[(s-1)*glbs.Ndens+j] = getIndexOf(glbs.trees[j], glbs.ind[j])+1;  # return particle label
        end

        samplePoint!(glbs.newPoints, glbs, frm);                            # draw a sample from that label
               #glbs.newIndices = glbs.newIndices[glbs.Ndens:end]  # move pointers to next sample
               #glbs.newPoints  = glbs.newPoints[glbs.Ndim:end]
        #printGlbs(glbs, string("s=",s-1))
    end
    ##@show glbs.ruptr, size(glbs.randU), size(glbs.randU,1)+glbs.ruptr
    # deref the glbs data and let gc() remove it later, or force with gc()
    glbs = 0
    #@show @elapsed gc()
    #error("gibbs1 -- not implemented yet")
    nothing
end

# function remoteProdAppxMSGibbsS(npd0::BallTreeDensity,
#                           npds::Array{BallTreeDensity,1}, anFcns, anParams,
#                           Niter::Int64=5)
#
#   len = length(npds)
#   arr = Array{Array{Float64,2},1}(len)
#
#   d = npds[1].bt.dims
#   N = npds[1].bt.num_points
#
#
#   for i in 1:len
#     arr[i] = reshape(npds[i].bt.centers[(N*d+1):end],d,N)
#   end
#
#   pts, bw = remoteProd(arr)
#
#   return pts, -1
# end

function prodAppxMSGibbsS(npd0::BallTreeDensity,
                          npds::Array{BallTreeDensity,1}, anFcns, anParams,
                          Niter::Int64=5)
    # See  Ihler,Sudderth,Freeman,&Willsky, "Efficient multiscale sampling from products
    #         of Gaussian mixtures", in Proc. Neural Information Processing Systems 2003

    Ndens = length(npds)              # of densities
    Ndim  = npds[1].bt.dims           # of dimensions
    Np    = Npts(npd0)                # of points to sample

    # skipping analytic functions for now TODO ??

    UseAn = false
    #??pointsM = zeros(Ndim, Np)
    points = zeros(Ndim*Np)
    #??plhs[1] = mxCreateNumericMatrix(Ndens, Np, mxUINT32_CLASS, mxREAL);
    indices=ones(Int64,Ndens*Np)
    maxNp = Np                        # largest # of particles we deal with
    for tree in npds
        if (maxNp < Npts(tree))
            maxNp = Npts(tree)
        end
    end
    Nlevels = floor(Int64,(log(Float64(maxNp))/log(2.0))+1.0)  # how many levels to a balanced binary tree?

    # Generate enough random numbers to get us through the rest of this
    if true
      randU = rand(Int64(Np*Ndens*(Niter+2)*Nlevels))
      randN = randn(Int64(Ndim*Np*(Nlevels+1)))
    else
        randU = vec(readdlm("randU.csv"))
        randN = vec(readdlm("randN.csv"))
    end

    #@show size(randU), size(randN)
    gibbs1(Ndens, npds, Np, Niter, points, indices, randU, randN);

    return reshape(points, Ndim, Np), reshape(indices, Ndens, Np)
end

function *(p1::BallTreeDensity, p2::BallTreeDensity)
  numpts = round(Int,(Npts(p1)+Npts(p2))/2)
  d = Ndim(p1)
  d != Ndim(p2) ? error("kdes must have same dimension") : nothing
  dummy = kde!(rand(d,numpts),[1.0]);
  pGM, = prodAppxMSGibbsS(dummy, [p1;p2], Union{}, Union{}, 5)
  return kde!(pGM)
end
