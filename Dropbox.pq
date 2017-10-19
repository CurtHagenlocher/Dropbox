section Dropbox;

client_application = Expression.Evaluate(Text.FromBinary(Extension.Contents("client_application")));
windowWidth = 1200;
windowHeight = 1000;

TokenMethod = (code, grant_type) =>
    let
        Response = Web.Contents("https://api.dropbox.com/oauth2/token", [
            Content = Text.ToBinary(Uri.BuildQueryString([
                client_id = client_application[ClientId],
                client_secret = client_application[ClientSecret],
                grant_type = grant_type,
                code = code,
                redirect_uri = client_application[CallbackUrl]
            ])),
            Headers=[#"Content-type" = "application/x-www-form-urlencoded"]
        ]),
        Parts = Json.Document(Response)
    in
        Parts;

StartLogin = (resourceUrl, state, display) =>
    let
        AuthorizeUrl = "https://www.dropbox.com/oauth2/authorize?" & Uri.BuildQueryString([
            client_id = client_application[ClientId],
            response_type = "code",
            state = state,
            redirect_uri = client_application[CallbackUrl]])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = client_application[CallbackUrl],
            WindowHeight = windowHeight,
            WindowWidth = windowWidth,
            Context = null
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        Parts = Uri.Parts(callbackUri)[Query]
    in
        TokenMethod(Parts[code], "authorization_code");

Refresh = (resourceUrl, refresh_token) => TokenMethod(refresh_token, "refresh_token");

Table.GenerateByPage = (getNextPage as function) as table =>
    let
        listOfPages = List.Generate(
            () => getNextPage(null),
            (lastPage) => lastPage <> null,
            (lastPage) => getNextPage(lastPage)
        ),
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        if (firstRow = null) then
            Table.FromRows({})
        else
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

GetFile = (id) => Web.Contents("https://content.dropboxapi.com/2/files/download", [
        Headers=[#"Dropbox-API-Arg"=Text.FromBinary(Json.FromValue([path=id]))],
        Content = #binary({})
    ]);

// TODO: add paging based on this cursor and/or the "has_more" value
GetDirectory = (dir) =>
    let
        source = Web.Contents("https://api.dropboxapi.com/2/files/list_folder", [
            Headers=[#"Content-Type"="application/json"],
            Content = Json.FromValue([
                path = dir,
                recursive = false,
                include_media_info = false,
                include_deleted = false,
                include_has_explicit_shared_members = false
            ])
        ]),
        json = Json.Document(source),
        cursor = json[cursor]?,
        table = Table.FromList(json[entries], Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        expanded = Table.ExpandRecordColumn(table, "Column1", {".tag", "id", "name", "path_display", "client_modified", "server_modified", "size", "content_hash", "rev", "shared_folder_id", "sharing_info"}),
        added = Table.AddColumn(expanded, "Content", each if [#".tag"] = "file" then GetFile([id]) else GetDirectory([path_display]))
    in
        added;

[DataSource.Kind = "Dropbox"]
shared Dropbox.Contents = () => GetDirectory("");

Dropbox = [
    Authentication=[OAuth=[StartLogin=StartLogin, FinishLogin=FinishLogin, Refresh=Refresh]]
];
