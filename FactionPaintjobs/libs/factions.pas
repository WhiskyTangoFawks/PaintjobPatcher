unit FPD_Factions;

var
    config_factions, config_options : TMemIniFile;
    fact_name, fact_kywd, fact_alt_kywds, fact_paintjobs, fact_filter_paint, fact_filter_lvli, fact_filter_item : integer;
    listMaster, listFactions, listDefaultFactions, listEpicFactions, listDefaultPaSets, listEpicPaSets: TStringList;
    filter_paintjob_ap, filter_paintjob_kywd, filter_allow_redistribute, filter_eval_furn, filter_eval_item, filter_eval_omod, filter_eval_lvli: TStringList;

//============================================================================
// Configuration
//============================================================================
procedure initConfig();

begin
    logg(1, 'Loading Config.ini');
    config_options := TMemIniFile.Create('Edit Scripts\FactionPaintjobs\Config.ini');
    filter_paintjob_ap := getConfigList(config_options, 'Config', 'filter_paintjob_ap');
    logg(1, 'Filter Paintjob AP list size = ' + intToStr(filter_paintjob_ap.count));
    filter_paintjob_kywd := getConfigList(config_options, 'Config', 'filter_paintjob_kywd');
    logg(1, 'Filter Paintjob KYWD list size = ' + intToStr(filter_paintjob_ap.count));
    filter_allow_redistribute := getConfigList(config_options, 'Config', 'filter_allow_redistribute');
    filter_eval_furn := getConfigList(config_options, 'Config', 'filter_eval_furn');
    filter_eval_item := getConfigList(config_options, 'Config', 'filter_eval_item');
    filter_eval_lvli := getConfigList(config_options, 'Config', 'filter_eval_lvli');
    filter_eval_omod := getConfigList(config_options, 'Config', 'filter_eval_omod');
    

end;

//================
procedure initFactions();
var
  i, j, p : integer;
  keywordString, filename, section : String;
  keyword : IInterface;
  tempFactions, factionValues, filterValues, temp : TStringList;

const
    ini_kywd = 'keyword';
    ini_alt_keywords = 'alt_keywords';
    ini_filterItemType = 'filter_item_type';
    ini_isDefaultPA  = 'is_default_pa';
    ini_isEpicPa = 'is_epic_pa';
    ini_filter_lvli = 'filter_lvli';
    ini_filter_paint = 'filter_paintjob';   
    ini_filter_item = 'filter_item';
    ini_is_default = 'is_default';
    ini_is_epic = 'is_epic';

begin
    logg(1, 'Loading Factions.ini');
    config_factions := TMemIniFile.Create('Edit Scripts\FactionPaintjobs\Factions.ini');
    
    listMaster := TStringList.create;
    listFactions := TStringList.create;
    listDefaultFactions := TStringList.create;
    listEpicFactions := TStringList.create;
    listDefaultPaSets := TStringList.create;
    listEpicPaSets := TStringList.create;
    
    tempFactions := TStringList.create;
    config_factions.readSections(tempFactions);
    //iterate the configured factions
    for i := 0 to tempFactions.count-1 do begin
        logg(1, 'Loading faction config: ' + tempFactions[i]);
        section := tempFactions[i];
        
        //Create the faction TStringList, add it to the master faction list, and whatever sub-lists it's configured for
        factionValues := TStringList.create;
        listMaster.addObject(tempFactions[i], factionValues);
        if (config_factions.readString(tempFactions[i], ini_is_default, '') = 'true') then listDefaultFactions.addObject(section, factionValues)
        else if (config_factions.readString(tempFactions[i], ini_is_epic, '') = 'true') then listEpicFactions.addObject(section, factionValues)
        else if (config_factions.readString(tempFactions[i], ini_isDefaultPA, '') = 'true') then listDefaultPaSets.addObject(tempFactions[i], factionValues)
        else if (config_factions.readString(tempFactions[i], ini_isEpicPA, '') = 'true') then listEpicPaSets.addObject(tempFactions[i], factionValues)
        else listFactions.addObject(tempFactions[i], factionValues);

        
        //index 0, Faction Name
        fact_name := 0;
        factionValues.addObject(tempFactions[i], tempFactions[i]);

        //index 1, the formID for the keyword
        fact_kywd := 1;

        keyword := generateFactionKeyword(tempFactions[i], config_factions.readString(tempFactions[i], ini_kywd, ''));
        factionValues.addObject(intToHex(GetLoadOrderFormID(keyword), 8), keyword);
    
        //index 2, alt keywords
        //load formID + IINterface into the tstringlist
        fact_alt_kywds := 2;
        temp := getConfigList(config_factions, tempFactions[i], ini_alt_keywords);
        filterValues := TStringList.create;
        for j := 0 to temp.count -1 do begin
            p := Pos('|', temp[j]);
            filename := Copy(temp[j], 1, p-1);
            keywordString := Copy(temp[j], P+1, Length(temp[j]));
            keyword := MainRecordByEditorID(GroupBySignature(fileByName(filename), 'KYWD'), keywordString);
            if not assigned(keyword) then raise Exception.create('** ERROR ** unable to find alt keyword ' + keywordString + ' in file ' + filename);
            filterValues.addObject(IntToHex(GetLoadOrderFormID(keyword), 8), keyword)
        end;
        factionValues.addObject(ini_alt_keywords, filterValues);

        //index 3, the faction paintjobs: <formId, IInterface>
        //starts empty, will be filled during OMOD evaluation
        fact_paintjobs := 3;
        factionValues.addObject('faction_paintjobs', TStringList.create);

        //index 4, the paintjob filter
        fact_filter_paint := 4;
        factionValues.addObject(ini_filter_paint, getConfigList(config_factions, tempFactions[i], ini_filter_paint));
        logg(1, tempFactions[i] + ': filter_paintjob count =' + intToStr(factionValues.objects[fact_filter_paint].count));
        
        //index 5, the lvli filter
        fact_filter_lvli := 5;
        factionValues.addObject(ini_filter_lvli, getConfigList(config_factions, tempFactions[i], ini_filter_lvli));
        logg(1, tempFactions[i] + ': filter_lvli count =' + intToStr(factionValues.objects[fact_filter_lvli].count));

        //index 6, the item filter
        fact_filter_item := 6;
        factionValues.addObject(ini_filter_item, getConfigList(config_factions, tempFactions[i], ini_filter_item));
        logg(1, tempFactions[i] + ': filter_item count =' + intToStr(factionValues.objects[fact_filter_item].count));

    end;
    logg(3, intToStr(tempFactions.count) + ' Configurations loaded');
    logg(3, intToStr(listDefaultFactions.count) + ' Default Factions loaded');
    logg(3, intToStr(listEpicFactions.count) + ' Epic Factions loaded');
    logg(3, intToStr(listFactions.count) + ' Standard Factions loaded');
    logg(3, intToStr(listDefaultPaSets.count) + ' Default PA Sets loaded');
    logg(3, intToStr(listEpicPaSets.count) + ' Epic PA Sets loaded');
    tempFactions.free;

end;

//=======
function generateFactionKeyword(faction, keyword: String): IInterface;
var
    p : integer;
    filename : String;
    newKeyword : IInterface;

begin
    //get the override keyword, if present, eg: fallout4.esm|if_tmp_atomcats
    logg(1, 'GenerateFactionKeyword: ' + keyword);
    
    if (keyword <> '') then begin
        p := Pos('|', keyword);
        filename := Copy(keyword, 1, p-1);
        keyword := Copy(keyword, P+1, Length(keyword));
        result := MainRecordByEditorID(GroupBySignature(fileByName(filename), 'KYWD'), keyword);
        if not assigned(result) then raise Exception.create('** ERROR ** unable to find keyword ' + keyword + ' in file ' + filename);
        logg(1, 'Found override keyword: ' + filename + '|' + keyword + ' : ' + editorId(result));
    end
    //else create the faction keyword
    else begin
        newKeyword := wbCopyElementToFile(template_keyword, mxPatchFile, true, true);
        setElementEditValues(newKeyword, 'EDID', 'if_tmp_' + faction);
        result := newKeyword;
        if not assigned(result) then raise Exception.create('** ERROR **failed to generate faction keyword');
        logg(1, 'Generated faction keyword ' + editorId(newKeyword));
    end;
end;

//=======
function getConfigList(config: TMemIniFile; faction, key: String): TStringList;
var
    str, prefix, suffix, filterString: String;
    i, suffixPos: integer;
    rawList, filter: TStringList;

begin
    str := config.readString(faction, key, '');
    str := trim(str);
    
    rawList := TStringList.create;
    rawList.Delimiter := ',';
    rawList.DelimitedText := str;

    result := TStringList.create;
    for i := 0 to rawList.count-1 do begin
        
        prefix := Copy(rawList[i], 1, 1);
        if (prefix = '+') or (prefix = '-') or (prefix = '!') or (prefix = '#') then begin
            filterString := Copy(rawList[i], 2, Length(rawList[i]) - 1);
        end else begin
            prefix := '';
            filterString := rawList[i];
        end;
        suffixPos := pos(':', filterString);
        if (suffixPos > 0) then begin
            suffix := copy(filterString, suffixPos+1, length(filterString));
            filterString := copy(filterString, 1, suffixPos-1);            
        end else suffix := '';

        filter := TStringList.create;
        result.AddObject(rawList[i], filter);
        filter.add(prefix);
        filter.add(filterString);
        filter.add(suffix);
        
    end;

    if (result.count < 1) then logg(3, 'Found empty faction filter: ' + faction + ' - ' +key);
    rawList.free;

end;

//============================================================================  
function getItemDefaultFaction(item: IInterface; cacheApprFormId, cacheKywdFormId: TStringList): TStringList;
var
    i: integer;
    faction: TStringList;
begin
    for i := 0 to listDefaultFactions.count-1 do begin
        faction := listDefaultFactions.objects[i];
        if isItemFiltered(item, faction.objects[fact_filter_item], cacheApprFormId, cacheKywdFormId) then begin
            result := faction;
            exit;
        end;
    end;
    logg(4, 'No default faction found for ' + editorId(item));
end;

//============================================================================  
function getItemEpicFaction(item: IInterface; cacheApprFormId, cacheKywdFormId: TStringList): TStringList;
var
    i: integer;
    faction: TStringList;
begin
    for i := 0 to listEpicFactions.count-1 do begin
        faction := listEpicFactions.objects[i];
        if isItemFiltered(item, faction.objects[fact_filter_item], cacheApprFormId, cacheKywdFormId) then begin
            //logg(1, 'Found epic faction ' + faction[fact_name] + ' for item' + editorId(item));
            result := faction;
            exit;
        end;
    end;
    logg(4, 'No epic faction found for ' + editorId(item));
end;
//============
function isLvliFiltered(lvli: IInterface; filterList: TStringList): boolean;
begin
    result := isRecordFiltered(lvli, editorId(lvli), filterList, nil, nil);
end;
//============
function isFurnFiltered(furn: IInterface; filterList: TStringList): boolean;
begin
    result := isRecordFiltered(furn, editorId(furn), filterList, nil, nil);
end;
//============
function isOmodFiltered(omod: IInterface; filterList: TStringList): boolean;
begin
    //TODO - use appr and keyword caches here too? Not necessary, but it would let me filter painjobs with keywords
    result := isRecordFiltered(omod, getElementEditValues(omod, 'FULL'), filterList, nil, nil);
end;
//============
function isKeywordFiltered(kywd: IInterface; filterList: TStringList): boolean;
begin
    result := isRecordFiltered(kywd, editorId(kywd), filterList, nil, nil);
end;
//============
function isItemFiltered(item: IInterface; filterList, cacheApprFormId, cacheKywdFormId: TStringList): boolean;
begin
    result := isRecordFiltered(item, getElementEditValues(item, 'FULL'), filterList, cacheApprFormId, cacheKywdFormId);
end;

//============================================================================  
function isRecordFiltered(rec: IInterface; value: string; filterList, cacheKywdFormId, cacheApprFormId: TStringList): boolean;
var
    countFilter: integer;
    value: String;
    hasText : boolean;
    filter : TStringList;
begin
    result := false;
    
    //Paintjobs are filtered based on their FULL, the rest are filtered based on EDID
    if signature(rec) = 'OMOD' then value := getElementEditValues(rec, 'FULL')
    else value := editorId(rec);

    if not assigned(filterList) then raise exception.create('**ERROR** Missing filter list');
    //iterate through the filter terms
    for countFilter := 0 to filterList.count-1 do begin
        filter := filterList.objects[countFilter];
        
        if (filter[2] = '') then hasText := containsText(value, filter[1])
        else if filter[1] = 'keyword' then hasText := (cacheKywdFormId.indexOf(filter[2]) <> -1)
        else if filter[1] = 'signature' then hasText := (signature(rec) = filter[2])
        else raise exception.create('Unrecognized filter string with suffix :' + filter[1]);

        if (filter[0] = '+') then begin
            //requires: if DOESN'T have this, return false and exit
            if not hasText then begin
                //logg(1, 'filtering: missing + filter, returning false: ' + value + ' - ' +  filterString);
                result := false;
                exit;
            end;
        end else if (filter[0] = '-') then begin
            //Blacklist: If has this, return false and exit
            if hasText then begin
                result := false;
                exit;
            end;
        end else if (filter[0] = '') then begin
            //no prefix: terminal entry. If has this filter keyword, then return true and exit
            if hasText then begin
                result := true;
                exit;
            end;
        end else if (filter[0] = '!') then begin
            //accept all, useful if you're doing a bunch of negative filtering before it
            result := true;
            exit;
        end else if (filter[0] = '#') then begin
            //Custom logic
            if containsText(filter[1], 'NoProperties') then begin
                if (signature(rec) <> 'OMOD') then raise exception.create('Called NoProperties on a non-OMOD record filter');
                if (elementCount(ElementByPath(rec, 'DATA\Properties')) = 0) then begin
                    result := true;
                    exit;
                end;
            end
            else raise exception.create('Unrecognized logic qualifier #' + filter[1]);
        end
        else raise Exception.Create('**ERROR** encountered unexpected filter prefix: ' + filter[0]);
    end;
    result := false;
end;


//=======
function itemAlreadyHasTemplatesForFaction(item: IInterface; faction: TStringList): boolean;
var
    refBy, keyword : IInterface;
    i, countAlt: integer;
begin
    result := false;
    logg(1, 'Checking if ' + editorId(item) + ' already has templates for ' + faction[fact_name]);
    
    //check main keyword
    keyword := ObjectToElement(faction.objects[fact_kywd]);
    if getFileName(getFile(keyword)) <> getFileName(masterPlugin) then begin
        if isReferencedBy(item, keyword) then begin
            logg(2, 'found template with kywd ' + editorId(keyword) + ' on ' + editorId(item));
            result := true;
            exit;
        end;
    end;
    
    //check alt keywords
    for countAlt := 0 to faction.objects[fact_alt_kywds].count-1 do begin
        keyword := ObjectToElement(faction.objects[fact_alt_kywds].objects[countAlt]);
        if getFileName(getFile(keyword)) <> getFileName(masterPlugin) then begin
            if isReferencedBy(item, keyword) then begin
                logg(2, 'found template with alt kywd ' + editorId(keyword) + ' on ' + editorId(item));
                result := true;
                exit;
            end;
        end;
    end;
end;

//=======
function isReferencedBy(item, keyword: IInterface): boolean;
var
    refBy:  IInterface;
    i: integer;
begin
    result := false;
    for i := 0 to ReferencedByCount(keyword) -1 do begin
        refBy := ReferencedByIndex(keyword, i);
        if not isWinningOverride(refBy) then continue;
        if getLoadOrderFormId(refBy) <> getLoadOrderFormId(item) then continue;

        result := true;
        exit;
    end;

end;


//============================================================================  
procedure removeFactionsWithNoPaintjobs();
var
    i: integer;
    faction: TStringList;
begin
    for i := listDefaultFactions.count-1 downto 0 do 
        if (listDefaultFactions.objects[i].objects[fact_paintjobs].count = 0)
            then listDefaultFactions.delete(i);
    
    for i := listEpicFactions.count-1 downto 0 do 
        if (listEpicFactions.objects[i].objects[fact_paintjobs].count = 0)
            then listEpicFactions.delete(i);
    
    for i := listFactions.count-1 downto 0 do 
        if (listFactions.objects[i].objects[fact_paintjobs].count = 0)
            then listFactions.delete(i);
    
    for i := listDefaultPaSets.count-1 downto 0 do 
        if (listDefaultPaSets.objects[i].objects[fact_paintjobs].count = 0)
            then listDefaultPaSets.delete(i);

    for i := listEpicPaSets.count-1 downto 0 do 
        if (listEpicPaSets.objects[i].objects[fact_paintjobs].count = 0)
            then listEpicPaSets.delete(i);
        
end;


end.