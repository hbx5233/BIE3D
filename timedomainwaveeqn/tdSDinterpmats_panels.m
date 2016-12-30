function [Sret Dret] = tdSDinterpmats_panels(tpan,span,paninfo,intinfo)
%
% [Sret Dret] = tdSDinterpmats_panels(tpan,span,paninfo,intinfo)
%
% eval p^2-by-NT matrices which apply retarded S,D ops from dens hist grids
%
% where N is # dofs in all src pans.
%
% intinfo has fields: n = # history steps, dt = timestep, m = interp order.

% tpan single panel for now. Includes aux node close & self-eval.

% See also: TEST_TDGRF_INTERP.m which tests this (near bottom).

% Barnett 12/29/16

M = size(getallnodes({tpan}),2);          % # targets
t = tpan;
if numel(span)==1, span = {span}; end
% ** idea: loop through all span, tra
% If it's a self-or-nei of t, then treat each targ node in t separately,
% since they have own aux nodes (to get spatial sing correct).
% Will need to make dummy targ panel w/ 1 node, loop over t's targ nodes.
Sret = []; Dret = [];
for q=1:numel(span), s = span{q};    % loop over src pans in right order
  r = relatedpanel(t,s);
  if r==0
    [Sq Dq] = tdSDinterpmats_panelpair(t,s,intinfo);
  else    % s is self or nei of t
    % ***
  end
  Sret = [Sret, Sq]; Dret = [Dret, Dq];   % stack each pan as block col
end

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
[jmax jmin A Ap] = interpmat(-delays(:),o.dt,o.m);  % Tom's weights (1 row per delay, ordered fast over sources, slow over targs)
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
Dret = sparse(ii,jj,dd,M,N*n);            % (only the value part so far)
% *** todo: find neater way to build this without repeating the find()...
% (issue is want sparsity pattern that includes A and Ap...)
ii = []; jj = []; dd = [];  % to build the deriv part of DLP
for k=1:M     % loop over targs
  [j i a] = find(Ap((1:N)+(k-1)*N,:)');   % j is time inds, i is src inds (slow)
  dd = [dd; a.*Dp(k,i)'];                 % deriv part of DLP
  ii = [ii; k*ones(size(a))];
  jj = [jj; joff+j+n*(i-1)];              % time indices in the Nn vector
end
Dret = Dret + sparse(ii,jj,dd,M,N*n);  % may have slightly different patterns
