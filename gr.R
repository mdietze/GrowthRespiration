require(PEcAn.all)
logger.setQuitOnSevere(FALSE)
settings <- read.settings("gr.settings.xml")
get.trait.data()

## rescale trait data
trait.file = file.path(settings$pfts$pft$outdir, 'trait.data.Rdata')
load(trait.file)
for(i in 1:length(trait.data)){
    trait.data[[i]]$mean = trait.data[[i]]$mean/100
    trait.data[[i]]$stat = trait.data[[i]]$stat/100
}
save(trait.data,file=trait.file)

##PEcAn - get posterior priors
run.meta.analysis()
load(file.path(settings$pfts$pft$outdir,"trait.mcmc.Rdata"))
load(file.path(settings$pfts$pft$outdir,"post.distns.Rdata"))

#R = Rl + Rs + Rr

#leaf
#Rl = kl*Gl
#kl = cost (g C produced) * pcompl (percent composition of leaf components)

c <- read.csv("cost.csv")
cost <- c$CO2Produced
NC <- length(cost) # #Components

## Convert gCO2 to gC
## gCO2*(12gC/44gCO2)
cost = cost*(12/44)

## calc mean and sd from meta-analysis

mean = matrix(NA,NC,3)
var = matrix(NA,NC,3)

leafvariables = c('l_carbohydrates','l_lignin','l_lipids','l_minerals','l_organicacids','l_protein')
stemvariables = c('s_carbohydrates','s_lignin','s_lipids','s_minerals','s_organicacids','s_protein')
rootvariables = c('r_carbohydrates','r_lignin','r_lipids','r_minerals','r_organicacids','r_protein')

variables=matrix(c(leafvariables,stemvariables,rootvariables),NC,3)
NV=length(variables) #Number of variables

for(i in 1:NV){
  if(variables[i] %in% names(trait.mcmc)){
    y = as.matrix((trait.mcmc[[variables[i]]]))[,"beta.o"]
    mean[i]= mean(y)
    var[i]= var(y)
  } else {
    ## use the prior
    row = which(rownames(post.distns) == variables[i])
    if(length(row)==1 & post.distns$distn[row] == 'beta'){
      x = post.distns[row,]
      mean[i] = x$parama/(x$parama+x$paramb)
      var[i]  = (x$parama*x$paramb)/((x$parama+x$paramb)^2*(x$parama+x$paramb+1)^2)    
    }
  }
}

## moment matching to est. alpha
    # USING DIRICHLET:
    # mean[i]=a[i]/a0
    # var[i]=a[i]*(a0-a[i])/((a0)^2*(a0+1))
      # a = matrix(NA,NC,3)
      # for(i in 1:length(variables)){
        # a[i]=mean[i]*(((mean[i]-mean[i]^2)/var[i])-1)
        # }
# USING BETA
  # E[x]=M=a/(a+B)
    # B=a(1-M)/M
  # Var[X]=aB/[(a+B)^2(a+B+1)]
a=B=matrix(NA,NC,3)
for(i in 1:NV) {
  #a[i]=(1-mean[i])/var[i]-mean[i]
  #B[i]=(1-mean[i])^2/var[i]-1+mean[i]
  a[i]=(1-mean[i])*mean[i]^2/var[i]-mean[i]
  B[i]= a[i]*(1-mean[i])/mean[i]
}

NewP.oldDoesntWork <- function(k,p,a,b){
  # calculate current quantile
  q0 = pbeta(p,a,b)
  qm = pbeta(a/(a+b),a,b)
  
  # adjust by k
  qnew = qm + k*(q0-qm)
  qnew[qnew<0] = 0
  qnew[qnew>1] = 1
  
  # convert back to p
  pnew = qbeta(qnew,a,b)
  return(pnew)  
}

NewP <- function(k,p,a,b){
  # calculate current quantile
  q0 = pbeta(p,a,b)

  # calc SD equivalent of current quantile
  sd0 = qnorm(q0)
  
  # adjust by k
  sd.new = sd0 + k
  
  # calc new quantile
  q.new = pnorm(sd.new)
    
  # convert back to p
  pnew = qbeta(q.new,a,b)
  return(pnew)  
}

SumToOneFactor <- function(k,p,a,b){
  pnew = NewP(k,p,a,b)
  # assess sum to 1
  return((sum(pnew)-1)^2)
}

N = 5000#00 # Iterations
## l=leaf; s=stem; r=root; nd=assuming no parameter data
G=Gl=Gs=Gr=matrix(1,N,1)
Rl=Rs=Rr=Rnd=matrix(NA,N,1)
pcompl=pcomps=pcompr=pcompnd=matrix(NA,N,NC) #storage for % composition
kl=ks=kr=knd=matrix(NA,N,1) #cost*%composition

for(i in 1:N){
  # rdirichlet(1,c(,1,1,1,1,1))
  # pcompl[i,]=rdirichlet(1,c(a[,1]))
  # pcomps[i,]=rdirichlet(1,c(a[,2]))
  # pcompr[i,]=rdirichlet(1,c(a[,3]))
  for (j in 1:NC) {
    pcompnd[i,j]=rbeta(1,1,5)  
    pcompl[i,j]=rbeta(1,a[j,1],B[j,1]) 
    pcomps[i,j]=rbeta(1,a[j,2],B[j,2]) 
    pcompr[i,j]=rbeta(1,a[j,3],B[j,3])
  }
  ## Rescale pcomp output so sums to 1
  kopt = optimize(SumToOneFactor,c(-10,10),p=pcompnd[i,],a=1,b=6)
  popt = NewP(kopt$minimum,p=pcompnd[i,],a=1,b=6)
  
  koptl = optimize(SumToOneFactor,c(-10,10),p=pcompl[i,],a=a[,1],b=B[,1])
  poptl = NewP(koptl$minimum,p=pcompl[i,],a=a[,1],b=B[,1])
  
  kopts = optimize(SumToOneFactor,c(-10,10),p=pcomps[i,],a=a[,2],b=B[,2])
  popts = NewP(kopts$minimum,p=pcomps[i,],a=a[,2],b=B[,2])
  
  koptr = optimize(SumToOneFactor,c(-10,10),p=pcompr[i,],a=a[,3],b=B[,3])
  poptr = NewP(koptr$minimum,p=pcompr[i,],a=a[,3],b=B[,3])
  
  knd[i,]=sum(cost*popt)
  kl[i,]=sum(cost*poptl)
  ks[i,]=sum(cost*popts)
  kr[i,]=sum(cost*poptr)
  
  if(i %% 1000 == 0) print(i)

}

Rnd=knd*G  ## UNINFORMATIVE PRIOR; no percent composition data
Rl=kl*Gl
Rs=ks*Gs
Rr=kr*Gr

R=Rl+Rs+Rr
cols = 1:4
dRnd = density(Rnd)
plot(density(Rl),xlim=range(dRnd$x),col=cols[2])
lines(dRnd,col=cols[1])
lines(density(Rs),col=cols[3])
lines(density(Rr),col=cols[4])
legend("topright",legend=c("Null","Leaf","Stem","Root"),col=cols,lwd=2)

## Variance Decomposition
## sum(Pcomp^2*Var(cost) + sum(cost^2*Var(Pcomp))  ## no variance in construction costs
vd = matrix(NA,NC,3)

for (i in 1:NC){
  vd[i,1]=cost[i]^2*var(pcompl[,i])
  vd[i,2]=cost[i]^2*var(pcomps[,i])
  vd[i,3]=cost[i]^2*var(pcompr[,i])
}

## alternative that doesn't have sum to 1 constraints
for (i in 1:NC){
  vd[i,1]=cost[i]^2*var[i,1]
  vd[i,2]=cost[i]^2*var[i,2]
  vd[i,3]=cost[i]^2*var[i,3]
}

colnames(vd) <- c("leaf","stem","root")
rownames(vd) <- c("carb","lignin","lipid","mineral","OA","protein")

totvar <- apply(vd,2,sum)
t(vd)/totvar  ##  % variance

totsd <- apply(sqrt(vd),2,sum)
t(sqrt(vd))/totsd *100 ##  % sd


###PCA
  
## Build covariates table

ctable=matrix(NA,1,length(variables))
colnames(ctable) <-variables

for(i in 1:length(variables)){
  ##Find variable in trait data
  if(variables[i]%in%names(trait.data)){
    tr=which(names(trait.data)==variables[i])
    ##Create unique ID for trait
    v=paste(trait.data[[tr]]$specie_id,trait.data[[tr]]$site_id,sep="#")
    for(j in 1:length(v)){
      ##if ID is already has a row in the table
      if(v[j]%in%rownames(ctable)){
        rownumber=which(rownames(ctable)==v[j])
        if(is.na(ctable[rownumber,i])) {
          ctable[rownumber,i]=trait.data[[i]]$mean[j]
        } else  {
        ####But if space in table already full
        ##average current and new value
          ctable[rownumber,i]==mean(c(ctable[rownumber,i],trait.data[[i]]$mean[j]))
        }
      } else{
        ##if ID is new
        newrow=matrix(NA,1,length(variables))
        rownames(newrow)=v[j]
        newrow[,i]=trait.data[[i]]$mean[j]
        ctable=rbind(ctable,newrow)
      }
    }
  }
}

## fit missing data model to estimate NAs
MissingData = "
model{
  for(i in 1:n){
    x[i,] ~ dmnorm(mu,tau)
  }
  mu ~ dmnorm(m0,t0)
  tau ~ dwish(R,k)
}
"
w = ncol(ctable)
data <- list(x = ctable,n=nrow(ctable),m0=rep(1/6,w),t0 = diag(1,w),R = diag(1e-6,w),k=w)

j.model = jags.model(file=textConnection(MissingData),
                     data = data,
                     n.chains=1,
                     n.adapt=10)



## leaves: leafretention, fall conspicuous
## stem:bloat (none for woody), growth rate, growth form, height, low growing grass
## roots: root depth, nitrogen fixation

    