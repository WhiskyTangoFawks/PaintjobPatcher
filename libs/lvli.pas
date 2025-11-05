unit FPD_lvli;

//============================================================================
function processLVLI(lvli: IInterface): boolean;
var
    i : integer;
    faction: TStringList;
    lvliEditorId: string;
begin
    if (winningRefByCount(lvli) < 1) then exit; //skip unused levelled lists
    if hasFactionKeyword(lvli) then exit; //If a lvli already has a filter keyword, skip it
    if not isLvliFiltered(lvli, filter_eval_lvli) then exit;

    lvliEditorId := EditorID(lvli);
    addMessage('***** Processing '+ lvliEditorId + ' '+ IntToHex(GetLoadOrderFormID(lvli), 8) + ' *****');
    //If the editorID contains one of the faction search terms, then flag it for patching.
    for i := 0 to listFactions.count-1 do begin
        faction := listFactions.objects[i];
        //skip to next if
        if not isLvliFiltered(lvli, faction.objects[fact_filter_lvli]) then continue;
        lvli := copyOverrideToPatch(lvli);
        addFilterKeywordToLVLI(lvli, faction[fact_kywd]);
        exit;
    end;

    if (containsText(lvliEditorId, 'CustomItem_') OR containsText(lvliEditorId, 'Aspiration')) then begin
        lvli := copyOverrideToPatch(lvli);
        addFilterKeywordToLVLI(lvli, intToHex(epic_kywd_formId, 8));
    end;
    
end;
//============================================================================
function addFilterKeywordToLVLI(lvli: IInterface; keywordFormId: String): boolean;
var
    filters, entry: IInterface;

begin
    logg(1, 'Adding filter keyword ' + keywordFormId + ' to ' + editorId(lvli));
    if not assigned(keywordFormId) OR (keywordFormId = '00000000') then raise exception.create('**ERROR** - addFilterKeywordToLVLI called without a keyword form id');
    filters := ElementByPath(lvli, 'LLKC');
    if not assigned(filters) then begin 
        Add(lvli, 'LLKC', true);
        filters := ElementByPath(lvli, 'LLKC');
        entry := elementByIndex(filters, 0);
    end else 
        entry := ElementAssign(ElementByPath(lvli, 'LLKC'), HighInteger, nil, False);
    
    SetEditValue(elementByPath(entry, 'Keyword'), keywordFormId);
    SetEditValue(elementByPath(entry, 'Chance'), 100);
    exit;
    
end;
//============================================================================
//returns whether a levelled list already has a faction  keyword
function hasFactionKeyword(lvli: IInterface): boolean;
var
  i, countFaction, alt: integer;
  llkcs, keyword, factKeyword : IInterface;
  faction, altKeywords : TStringList;
begin
    result := false;
    //Iterate the filter keywords
    llkcs := ElementByPath(lvli, 'LLKC'); 
    for i := 0 to ElementCount(llkcs)-1 do begin
        keyword := linksTo(elementByPath(elementByIndex(llkcs, i), 'Keyword'));
        
        //iterate the faction keywords
        for countFaction := 0 to listFactions.count-1 do begin
            //check base keyword
            faction := listFactions.objects[countFaction];
            //logg(1, 'comparing keyword ' +  editorId(keyword) + ' = ' + editorId(ObjectToElement(faction.objects[fact_kywd])));
            if GetLoadOrderFormID(keyword) = GetLoadOrderFormID(ObjectToElement(faction.objects[fact_kywd])) then begin
                result := true;
                exit;
            end;
            //check alt keywords
            altKeywords := faction.objects[fact_alt_kywds];
            for alt := 0 to altKeywords.count-1 do begin
                //logg(1, 'comparing alt keyword ' +  editorId(keyword) + ' = ' + editorId(ObjectToElement(altKeywords.objects[alt])));
                if getLoadOrderFormId(keyword) = GetLoadOrderFormID(ObjectToElement(altKeywords.objects[alt])) then begin
                    result := true;
                    exit;
                end;
            end;
            
            //Check for Epic keyword
            if GetLoadOrderFormID(keyword) =epic_kywd_formId then begin
                result := true;
                exit;
            end;
            
        end;
    end;
    result := false;   
end;

end.