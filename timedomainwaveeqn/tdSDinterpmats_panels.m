function [Sret Dret] = tdSDinterpmats_panels(tpan,span,Linfo,intinfo)
%
% [Sret Dret] = tdSDinterpmats_panels(tpan,span,Linfo,intinfo)
%
% eval p^2-by-NT matrices which apply retarded S,D ops from dens hist grids
%
% where N is # dofs in all src pans.
%
% tpan - target "panel" (ie has fields t.x, t.N)
%       If is same as a source panel in span, tpan must have auxnodes.
% Linfo - interpolation struct for the one std panel (from setup_auxinterp).
% intinfo - time-interp struct, has fields:
%         n = # history steps, dt = timestep, m = interp order.
%
% tpan single panel for now. Includes aux node close & self-eval.
%
% See also: TEST_TDGRF_INTERP.m which tests this (near bottom).

% Barnett 12/29/16 - 1/4/17
if nargin==0, test_tdSDinterpmats_panels; return; end

if numel(tpan)==1, tpan = {tpan}; end
M = size(getallnodes(tpan),2);          % # target nodes
if numel(span)==1, span = {span}; end
N = size(getallnodes(span),2);          % # source nodes
n = intinfo.n;
S.i = []; S.j = []; S.v = []; S.ptr = 0; D = S;          % sparse lists
roff = 0;                           % track roww offset in sparse mat out
for i=1:numel(tpan), t = tpan{i};   % ----- outer targ panel loop
  fprintf('targ pan #%d...\n',i)
  coff = 0;                           % track column offset for sparse mat out
  nnzmax = ceil(20*N);                % allocation size for Si,Di targ-pan NNZ
  Si.i = nan(nnzmax,1); Si.j = Si.i; Si.v = Si.i; Si.ptr = 0;
  Di = Si;
  for q=1:numel(span), s = span{q};   % loop over src pans in right order
    r = relatedpanel(t,s);
    if r==0    % s is unrelated, ie far from t
      [Sq Dq] = tdSDinterpmats_panelpair(t,s,intinfo);
    else    % s is self or nei of t
      nN = s.N*n;
      Sq = nan(t.N,nN); Dq = Sq;
      for j=1:t.N             % loop over targs and write each as row of Sq
        tj.x = t.x(:,j); tj.N = 1;    % this targ pt as own struct
        i = Linfo.auxindsbytarg{r}{j};  % indices in full list of aux nodes
        saux.x = t.auxnodes(:,i);   % here i indexes the last 2 dims naux*N
        saux.nx = t.auxnormals(:,i);
        saux.w = t.auxwei(i);
        saux.N = numel(saux.w);
        [Sa Da] = tdSDinterpmats_panelpair(tj,saux,intinfo);  % saux as src pan
        Ltjsaux = Linfo.Lbytarg{r}{j};     % see: setup_auxinterp
        Sq(j,:) = reshape(reshape(Sa,[n saux.N]) * Ltjsaux, [1 nN]);
        Dq(j,:) = reshape(reshape(Da,[n saux.N]) * Ltjsaux, [1 nN]);
      end
    end
    %  dump each src blk into sparse lists for this targ panel...
    [ii jj vv] = find(Sq); nh=numel(ii); hh = Si.ptr+(1:nh); Si.ptr = Si.ptr+nh;
    Si.i(hh) = ii+roff;  Si.j(hh) = jj+coff;  Si.v(hh) = vv;
    [ii jj vv] = find(Dq); nh=numel(ii); hh = Di.ptr+(1:nh); Di.ptr = Di.ptr+nh;
    Di.i(hh) = ii+roff;  Di.j(hh) = jj+coff;  Di.v(hh) = vv;
    coff = coff + size(Sq,2);
  end
  % dump each targ blk row into sparse lists... (don't append; too slow!)
  hh = S.ptr+(1:Si.ptr); S.ptr=S.ptr+Si.ptr;  % inds in final sparse list
  S.i(hh)=Si.i; S.j(hh)=Si.j; S.v(hh)=Si.v;
  hh = D.ptr+(1:Di.ptr); D.ptr=D.ptr+Di.ptr;  % inds in final sparse list
  D.i(hh)=Di.i; D.j(hh)=Di.j; D.v(hh)=Di.v;
  roff = roff + t.N;
end                                   % ------
Sret = sparse(S.i,S.j,S.v,M,n*N);     % build whole matrix in one go
Dret = sparse(D.i,D.j,D.v,M,n*N);

% Notes: spreplace here was too slow:
% https://www.mathworks.com/matlabcentral/answers/69528-sparse-matrix-more-efficient-assignment-operation
% Also, repeated append too slow


%%%%%%
function [Sret Dret] = tdSDinterpmats_panelpair(t,s,o)
% Inputs:
% t - target panel struct with: t.x - 3xM target locs
% s - source panel struct with: s.x, s.nx - 3xN locs and normal, s.w 1xN weights
% o - interpolation info struct with fields: n (# history steps), dt, m.
% Outputs:
% Sret,Dret - M-by-Nn sparse matrices, each row of which is a vector to apply
%             appropriately retarded SLP or DLP to density history vectors
%             (ordered with time fast, nodes slow) for that row's target.
%             Thus these matrices can do true matvecs against dens history.
% Barnett 12/29/16
n = o.n;
M = size(t.x,2); N = numel(s.w);        % # targs, # srcs
[S D Dp] = tdSDmats(t.x,s.x,s.nx,s.w);  % spatial quadr mats, each is MxN
delays = dists(s.x,t.x);                % pt pairwise time delays >0, transpose
[~,jmin,A,Ap] = interpmat(-delays(:),o.dt,o.m);  % Tom's weights (1 row per delay, ordered fast over sources, slow over targs)
joff = jmin+o.n-1;         % padding on the ancient side
if joff<0, error('interp requesting too ancient history!'); end
ii = []; jj = []; aa = []; dd = [];  % to build the sparse mats
for k=1:M     % loop over targs
  [j i a] = find(A((1:N)+(k-1)*N,:)');    % j is time inds, i is src inds (slow)
  aa = [aa; a.*S(k,i)'];                  % SLP spatial kernel & quadr wei
  dd = [dd; a.*D(k,i)'];                  % value part of DLP
  ii = [ii; k*ones(size(a))];
  jj = [jj; joff+j+n*(i-1)];              % time indices in the Nn vector
end
Sret = sparse(ii,jj,aa,M,N*n);
for k=1:M     % loop over targs, now appending to i,j,val lists for deriv part:
  [j i a] = find(Ap((1:N)+(k-1)*N,:)');   % j is time inds, i is src inds (slow)
  dd = [dd; a.*Dp(k,i)'];                 % deriv part of DLP
  ii = [ii; k*ones(size(a))];
  jj = [jj; joff+j+n*(i-1)];              % time indices in the Nn vector
end
Dret = sparse(ii,jj,dd,M,N*n);            % may have different pattern from Sret
% *** todo: find neater way to build this without repeating the find()... ?
% (issue is want sparsity pattern that includes A and Ap)

%%%%%
function test_tdSDinterpmats_panels   % do off/on surf wave eqn GRF test,
% taken from test_tdGRF_interp.  Barnett 1/1/17
side = 0;    %  GRF test:   1 ext, 0 on-surf
bigtest = 1;   % use all pans as on-surf targs
dt = 0.1;   % timestep
m = 4;      % control time interp order (order actually m+2)

so.a=1; so.b=0.5; o.p=6;
[s N] = create_panels('torus',so,o); % surf: default # pans
[x nx w] = getallnodes(s);
distmax = 4.0;       % largest dist from anything to anything
n = ceil(distmax/dt);

if side==1
  t.N = 1; t.x = [1.3;0.1;0.8];    % single test targ pt, exterior...
  Linfo = [];              % spatial interp info
else
  o.nr = 8; o.nt = 2*o.nr;     % first add aux quad to panels: aux quad orders
  s = add_panels_auxquad(s,o);
  if bigtest, t = s; else t = s{57}; end  % on-surf targ, 1 or more pans
  Linfo = setup_auxinterp(s{1}.t,o);  % std spatial interp to aux quad
end
ttarg = 0.0;          % test target time (avoids "t" panel field conflict)

% surf data for GRF...
w0 = 2.0; T = @(t) cos(w0*t); Tt = @(t) -w0*sin(w0*t); % data src t-func, tested
xs = [0.9;-0.2;0.1];   % src pt for data, must be inside
% eval sig, tau on {n history grid} x {N bdry nodes}
tt = dt*(-n+1:0); ttt = repmat(tt,[1 N]);
xx = kron(x,ones(1,n)); nxx = kron(nx,ones(1,n));   % ttt,xx,nxx spacetime list
[f,fn] = data_ptsrc(xs,T,Tt,ttt,xx,nxx);       % output ft unused
sighist = -fn; tauhist = f;  % col vecs, ext wave eqn GRF: u = D.u - S.un

tic, %profile clear; profile on
[Starg,Dtarg] = tdSDinterpmats_panels(t,s,Linfo,struct('n',n,'dt',dt,'m',m));
toc, %profile off; profile viewer

%[ii jj] = find(Dtarg); numel(ii)/prod(size(Dtarg)) % check sparsity
% tic, [ii jj aa] = find(Dtarg); toc % timing test

tic; u = Starg*sighist + Dtarg*tauhist; fprintf('t-step matvec in %.3g s\n',toc)
xtarg = getallnodes(t);
uex = data_ptsrc(xs,T,Tt,ttarg,xtarg);     % what ext GRF should give
if side==0, uex=uex/2; end   % on-surf principal value
fprintf('N=%d, dens-interp ext GRF test: max u err = %.3g\n',N,max(abs(u-uex)))
%u, uex
%whos   % 10MB, 1 sec per pan -> 1GB, 1 min for whole surf.
%keyboard

% todo *** try speeding up appending in _panelpair() - not much effect now