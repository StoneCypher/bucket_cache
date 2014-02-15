
% if it starts with a lower case letter, it's an "atom" (think enum)
% if it starts with an upper case letter, it's a variable.  they're all const
% get() and put() work with the "process dictionary," a k/v hash attached to the pid





-module(bucket_cache).





-export([

    setup/1,
    req/2,

    halt/1



    % internal

    cache_loop/0

]).





%% @doc spawn a new process, using cache_loop as its behavior; return its pid

setup() ->

    spawn( fun cache_loop/0 ).





%% @doc basically the constructor of the loop, handles init for this pid

cache_loop_setup() ->

    spawn_link( fun cache_janitor/0 ),    % spawn_link means when this process dies, so does that one
    cache_loop().





%% @doc the actual cleanup step (not implemented)

cache_cleanup() ->

    % put whatever cleanup you want here
    % like limit cache by size by oldest last_hit
    % or total count or whatever, i don't care

    ok.





%% @doc periodic cleanup process

cache_janitor() ->

    receive                    
        
        % nobody loves cache janitor

    after 10000 ->             % every ten seconds
        cache_cleanup()        % cleanup on your own

    end,

    cache_janitor().           % and repeat





%% @doc main workhorse loop for the cache

cache_loop() ->

    receive                                                 % get instructions


        terminate ->                                        % someone said exit

            exit(terminated);                                 % so exit



        { Origin, MessageHandle, request, R } ->            % got a fetch request
            
            Origin ! { MessageHandle, cache_req(R) },         % send back to the request origin what we get from cache_req/1
            cache_loop();                                     % loop



        { stash, R, Content } ->                            % got the instruction to cache something

            cache_insert(R,Content),                          % insert fresh into the cache
            cache_loop()                                      % loop


    end.





%% @doc insert fresh into the cache

cache_insert(R, Content) ->

    put({stash,R}, {now(),now(),Content}).





%% @doc update the last-read timestamp for a cache entry

cache_update_lastread(R) ->

    { Wrote, _Fetched, Content } = get({stash, R}),    % keep the write time and content
    put({stash,R}, {Wrote, now(), Content}).           % replace last-read time





%% @doc check the cache for a single request's cache

cache_req(R) ->
    
    case get({stash, R}) of                             % is it in stash?

        { Wrote,Fetched,Content } ->                      % yes, as {time,time,data}
            cache_update_lastread(R),                       % update last-fetched time
            { found, Content };                             % return the answer

        undefined ->                                      % no
            not_found                                       % return the non-answer

    end.





%% @doc make a cache request by message to the cache process.  
%%
%% if found: fetch, return.  
%%
%% if not, materialize, stash, return.
%%
%% timeout at two seconds, 'cause.

req(Request, CachePid, MaterializerFun) ->

    UniqueHandle = make_ref(),                                      % make a unique id for the message
    CachePid     ! { self(), UniqueHandle, request, Request },      % ask if the cacher has the content

    receive                                                         % fetch an answer


        { UniqueHandle, { found, Content } } ->                       % has the content

            Content;                                                    % cool, return it locally
 

        { UniqueHandle, not_found } ->                                % does not have the content

            Materialized = MaterializerFun(Request),                    % generate the content
            CachePid     ! { stash, Request, Materialized },            % send it to the cacher
            Materialized                                                % return it locally


    after 2000 ->                                                     % two seconds; give up

        timeout                                                         % tell local that you gave up


    end.





% just sends a terminate message to the appropriate pid

halt(Pid) ->

    Pid ! terminate.
