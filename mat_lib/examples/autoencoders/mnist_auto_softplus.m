function network = mnist_auto_softplus()
clc

n_samples = 1000;
n_samples_gmm = 3000;
max_steps = 10000;

opt.mini_batch = true;
opt.algorithm =  'momentum';
opt.learning_rate = 100.0;
opt.decay_steps = 500;
opt.momentum = 0.1;


opt.n_hidden = [150, 100, 10, 3]; %[150, 100, 8]
opt.n_kernels = 20;

opt.load = false;
opt.save = true;
%opt.weights_load_file = 'mnist_network_wp_relu_3h.mat'; % softplus [10, 5, 3, 3], lr = 10
%opt.weights_save_file = 'mnist_network_wp_relu_3h.mat'; % softplus [10, 5, 3, 3]

opt.weights_load_file = 'Data/mnist_softplus(_100_50_3_)02-Apr-2017 19:42:19.mat';
opt.weights_save_file = 'mnist_softplus';

%% 1. Load dataset
mnist = tdl.datasets.MnistDataset();

%% 2. Define the network
% [10 5 3] -> 0.0479, softplus with quasi-newton, 0.01 ridge

% parameters
n_inputs = 28*28;
n_hidden = opt.n_hidden; %[64, 3, 10 , 3]; %[100, 50, 3 , 3] working; 

n_dim = opt.n_hidden(end);
n_kernels = opt.n_kernels;

% create model
global network
network= NetworkModel( );

init_mul = 5;
x   = ConstantNode().atn();

w = cell(size(n_hidden));
b = cell(size(n_hidden));
c = cell(size(n_hidden));
wr = cell(size(n_hidden));
h = cell(size(n_hidden));
r = cell(size(n_hidden));


w{1}  = VariableNode([n_inputs, n_hidden(1)], init_mul).atn();     w{1}.name = 'w1';
b{1}  = VariableNode([1, n_hidden(1)], 0).atn();            b{1}.name = 'b1';
c{1}  = VariableNode([1, n_inputs], 0).atn();               c{1}.name = 'c1';

wr{1} = VariableNode([n_hidden(1), n_inputs], init_mul).atn();     wr{1}.name = 'wr1';

for l=2:length(n_hidden)
    w{l}  = VariableNode([n_hidden(l-1), n_hidden(l)], init_mul).atn();     w{l}.name = strcat('w', num2str(l));
    b{l}  = VariableNode([1, n_hidden(l)], 0).atn();            b{l}.name = strcat('b', num2str(l));
    c{l}  = VariableNode([1, n_hidden(l-1)], 0).atn();          c{l}.name = strcat('c', num2str(l));
    wr{l}  = VariableNode([n_hidden(l), n_hidden(l-1)], init_mul).atn();    wr{l}.name = strcat('wr', num2str(l));
end

%{ 
-- Using sigmoid activation functions, 2 layers
h{1}  = sigmoid(x*w1 + b1);                         h{1}.name = 'h1';  % original: sigmoid
h{2}  = h{1}*w2 + b2;                               h{2}.name = 'h2';
r{1}  = sigmoid(sigmoid(h{2}*w2'+ c2)*w1' + c1);    r{1}.name = 'r1';  % original: sigmoid, sigmoid
loss_r{1} = reduce_mean((r{1}-x).^2, [1, 2]);       l{1}.name = 'l1';

% reconstruction from input hidden layer
h_u = ConstantNode().atn();
x_u = sigmoid(sigmoid(h_u*w2'+ c2)*w1' + c1);    r{1}.name = 'x_u';
%}
%{ 
% -- Using relu activation functions, 2 layers
h{1}  = relu(x*w1 + b1);                            h{1}.name = 'h1';  % original: sigmoid
h{2}  = h{1}*w2 + b2;                               h{2}.name = 'h2';
r{1}  = sigmoid(relu(h{2}*w2'+ c2)*w1' + c1);       r{1}.name = 'r1';  % original: sigmoid, sigmoid
loss_r{1} = reduce_mean((r{1}-x).^2, [1, 2]) + 0.5.*(reduce_mean(w1.^2, [1, 2]) + reduce_mean(w2.^2, [1, 2]));       l{1}.name = 'l1';

% reconstruction from input hidden layer
h_u = ConstantNode().atn();
x_u = sigmoid(relu(h_u*w2'+ c2)*w1' + c1);    r{1}.name = 'x_u';
%}

% { 
% -- Using relu activation functions, 3 layers
h{1}  = x*w{1} + b{1};                                              h{1}.name = 'h1';     % 
reg = reduce_sum(w{1}.^2, [1, 2]) + reduce_sum(wr{1}.^2, [1, 2]);
for l=2:length(n_hidden)
    h{l} = softplus(h{l-1})*w{l} + b{l};                              h{l}.name = strcat('h', num2str(l));  % working: softplus
    reg = reg + (reduce_sum(w{l}.^2, [1, 2])).^0.5 + (reduce_sum(wr{l}.^2, [1, 2])).^0.5;
end

r{end} = h{end}*wr{end} + c{end};
for l=length(n_hidden)-1 : -1 : 1
    r{l} = softplus(r{l+1})*wr{l} + c{l};                           r{1}.name = strcat('r', num2str(l));
end
r{1} = sigmoid(r{1});
%r{1}  = sigmoid(softplus(softplus(h{3}*w3p+ c3)*w2p + c2)*w1p + c1);  r{1}.name = 'r1';  % workingl: sigmoid, softplus, softplus
loss_r{1} = reduce_mean((r{1}-x).^2, [1, 2]) + 0.00001.*reg;

% reconstruction from input hidden layer
h_u = ConstantNode().atn();
x_u = h_u*wr{end} + c{end};
for l=length(n_hidden)-1 : -1 : 1
    x_u = softplus(x_u)*wr{l} + c{l};
end

x_u = sigmoid(x_u);    x_u.name = 'x_u';
% }


% Gaussian mixture model
network_gmm= NetworkModel( );
[p_h] = network_gmm.add_node(GmmLayer(n_dim, n_kernels, 'diagonal')); %full, diagonal
[loss_gmm]= network_gmm.add_node(NegLogLoss(p_h));


% feed inputs
[train_x, ~] = mnist.train.next_batch(n_samples);
x.feed(train_x);


%% gradient check
%loss_dloss = @(w) tdl.loss_dloss(w, network, loss_r1);
%grad_check(loss_dloss, network.n_params, 200);

%% training function
iter = 0;
    function [loss, dloss] = loss_dloss(wt, model, target)        
        % get next batch
        if opt.mini_batch
            [train_x, ~] = mnist.train.next_batch(n_samples);
            x.feed(train_x);
        end
        
        % forward pass
        model.vect2params(wt);
        out = model.forward(target);
        loss= out{1};
        % backward pass
        dloss = model.backward(target);
        
        if mod(iter , 100)==0
            w_norm = zeros(length(n_hidden),1);
            for l=1:length(n_hidden)
                w_norm(l) = sqrt(sum(sum(w{l}.data.^2)));
            end
            w_norm'
            w_norm = zeros(length(n_hidden),1);
            for l=1:length(n_hidden)
                w_norm(l) = sqrt(sum(sum(wr{l}.data.^2)));
            end
            w_norm'
        end
        iter = iter + 1;
    end

    function [loss, dloss] = loss_dloss_gmm(w, model, target)        
        % get next batch
        %[train_x, ~] = mnist.train.next_batch(n_samples);
        %x.feed(train_x);
        
        % forward pass
        model.vect2params(w);
        out = model.forward(target);
        loss= out{1};
        % backward pass
        dloss = model.backward(target);
        
        iter = iter + 1;
    end


%% run training
if opt.load && exist(opt.weights_load_file, 'file')==2
    load_vars = load(opt.weights_load_file);
    w0 = load_vars.w_p;
    iter0 = load_vars.iter;
    max_steps = 1000;
else
    w0 = network.params2vect();
    iter0 = 0;
end

% 1. train autoencoder
for l = 1:1
    if l>1
        h{1}.node.propagate_gradients = false;
    end
    f = @(x)loss_dloss(x, network, loss_r{l});
        
    if strcmp(opt.algorithm, 'quasi-newton')
        options = optimoptions(@fminunc,'Algorithm','quasi-newton', ...
                                        'Display','iter', ...
                                        'MaxIterations', max_steps, ...
                                        'SpecifyObjectiveGradient', true);

        [w_p, train_loss_p] = fminunc(f, w0, options);
    elseif strcmp(opt.algorithm, 'momentum')
        options = tdl.optim.optimoptions(@tdl.optim.sgd,...
                         'Display', 100, ...
                         'MaxIterations', max_steps, ...
                         'LearningRate', @(i) opt.learning_rate*0.9^((i+iter0)/ opt.decay_steps), ... % 10 learning_rate*decay_rate^(global_step / decay_steps) , 100
                         'Momentum', opt.momentum, ... % 0.5
                         'MaxValue', 10e10 ...
                        );
        [w_p, train_loss_p] = tdl.optim.momentum_optimizer(f, w0, options);
    end
    w0 = w_p;
end

% save the parameters
if opt.save
    filename = strcat( opt.weights_save_file, ...
                       '(', sprintf('_%d', opt.n_hidden), '_)', ...
                       datestr(datetime), '.mat' );
    full_save_path = fullfile('Data', filename);
    save(full_save_path, 'w_p', 'iter', 'opt', 'train_loss_p');
    fprintf('Weights saved in %s', full_save_path);
end

% 2. train gaussian model on embedding
[train_x, ~] = mnist.train.next_batch(n_samples_gmm);
x.feed(train_x);

h_x = network.forward(h{end});

mu_h = mean(h_x{1});
sigma_h = std(h_x{1});
h_x = bsxfun( @times, (bsxfun(@plus, h_x{1}, -mean(h_x{1}))), 1./std(h_x{1}));

p_h.node.const.x = h_x;
f_gmm = @(x)loss_dloss_gmm(x, network_gmm, loss_gmm);
options = optimset('Display','iter', 'MaxIter', 100, 'GradObj','on');
[w_p, fval] = fminunc(f_gmm, network_gmm.params2vect() , options);

%% show reconstruction from original images
mat2img =  @(x) permute(reshape(x', 28, 28, 100), [2, 1, 3]);

[train_x, ~] = mnist.train.next_batch(100);
x.feed(train_x);
network.forward(r{1});

figure(1); tdl.datasets.imshow_batch(mat2img(x.data), 10, 10);
figure(2); tdl.datasets.imshow_batch(mat2img(r{1}.data), 10, 10);

h_u.feed(h{end}.data);
network.forward(x_u);
figure(3); tdl.datasets.imshow_batch(mat2img(x_u.data), 10, 10);


%% show reconstruction from sampled points
[~, gaussian_id] = max(p_h.node.w);

generated_x = [];
for gaussian_id = 1:opt.n_kernels
    sigma = squeeze(p_h.node.sigma(1, gaussian_id, :))';
    mu = squeeze(p_h.node.mu(1, gaussian_id, :))';
    h_samp = mvnrnd(mu, diag(sigma), 10);

    h_samp = bsxfun( @plus, bsxfun( @times, h_samp, sigma_h), mu_h);

    h_u.feed(h_samp);
    network.forward(x_u);
    generated_x = [generated_x; x_u.data];
end

figure(4); tdl.datasets.imshow_batch(mat2img(generated_x), opt.n_kernels, 10);

network.list_names()

%imshow(reshape(r1.data(1,:),28,28)')

end