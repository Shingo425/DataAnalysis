options mprint;

/* プロシジャ名をリセットするためのマクロ */
%macro reset_answer(api_key,model=gpt-4-turbo-preview,add_text="");
    %global answer; /* グローバル変数として答えを保持 */
    filename in temp; /* 一時ファイルの作成 */
    data _null_;
        length a $1000; /* JSON文字列のための変数 */
        file in; /* 一時ファイルへの書き込み */
        /* APIリクエストボディの作成 */
        a = cats('{"model": "',"&model.",'", "messages": [{"role": "user", "content":"SASのプロシジャ当てクイズを行うのでプロシジャをランダムに1つ提示してください。回答はPROCを除いたプロシジャ名のみ。',&add_text.,'"}]}');
        put a; /* 一時ファイルへのJSON文字列の書き込み */
    run;	
    /* APIリクエストの実行 */
    filename resp "%sysfunc(getoption(WORK))/echo.json";
    proc http
        method="POST"
        url="https://api.openai.com/v1/chat/completions"
        ct="application/json"
        in=in
        out=resp;
        headers "Authorization" = "Bearer &api_key.";
    run;
    /* JSONレスポンスの解析 */
    libname response JSON fileref=resp;
    
    /* 解析結果のフォーマット */
    data _null_;
        length outvar $6000;
        retain outvar "";
        set response.choices_message end=eof;
        do row=1 to max(1,countw(content,"0A"x));
            outvar=cats(outvar,scan(content,row,"0A"x));
        end;
        drop content;
        if eof then call symputx("answer",outvar); /* 結果をグローバル変数に格納 */
    run;
    
    /* 履歴データセットの初期化 */
    data history_ds;
        length user $1000 assistant $1000;
    run;
    
%mend;

/* アキネイタークイズの実行マクロ */
%macro akinator(text,history_ds,api_key,past_num=0,model=gpt-4-turbo-preview);
    /* ユーザー入力の履歴データセットへの追加 */
    data &history_ds.;
        length user $1000 assistant $1000;
        set &history_ds. end=eof;
        if user ne "" then output;
        if eof then do;
            user="&text.";
            output;
        end;	
    run;
    
    /* システムプロンプトの設定 */
    %let system_prompt="あなたはSASのプロシジャのアキネイター出題者。答えは「&answer.」。質問には「はい」「いいえ」「わかりません」で答えること。「答えは〜です。」の時のみ、「正解」「不正解」と回答。正解だった場合、軽く説明せよ。";
    
    /* APIリクエストボディの準備 */
    filename in temp;
    data _null_;
        file in;
        length a $6000;
        retain a;
        set &history_ds. nobs=nobs;
        /* システム、ユーザー、アシスタントメッセージを組み立て */
        if _n_=1 then a = cats('{"model": "',"&model.",'","messages": [{"role":"system","content":"',&system_prompt.,'"},');
        if nobs - &past_num.=<_n_ < nobs then a = cats(a, '{"role": "user", "content":"',user,'"},{"role":"assistant","content":"',assistant,'"},');
        if _n_ = nobs then do;
            a = cats(a, '{"role": "user", "content":"',user,'"}]}');	
            put a;
        end;
        run;

    /* APIリクエストの実行 */
    filename resp "%sysfunc(getoption(WORK))/echo.json";
    proc http
        method="POST"
        url="https://api.openai.com/v1/chat/completions"
        ct="application/json"
        in=in
        out=resp;
        headers "Authorization" = "Bearer &api_key.";
    run;
    /* JSONレスポンスの解析 */
    libname response JSON fileref=resp;
    
    /* 解析結果のフォーマット */
    data _null_;
        length outvar $6000;
        retain outvar "";
        set response.choices_message end=eof;
        do row=1 to max(1,countw(content,"0A"x));
            outvar=cats(outvar,scan(content,row,"0A"x));
        end;
        drop content;
        if eof then call symputx("outvar",outvar); /* 結果を変数に格納 */
    run;
    
    /* 履歴データセットへのアシスタント回答の追加 */
    data &history_ds.;
        set &history_ds. end=eof;
        if eof then assistant="&outvar.";
    run;
    
    /* 履歴データセットの表示 */
    proc print data=&history_ds.;
        var user assistant;
    run;
%mend;