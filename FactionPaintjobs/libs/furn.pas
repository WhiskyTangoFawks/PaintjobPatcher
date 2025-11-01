unit FPD_furn;

//============================================================================
function evalFurn(furn: IInterface): boolean;
var
    i, j: integer;
    items, lvli : IInterface;
begin
    result := false;
    if winningRefByCount(furn) < 1 then exit; //skip unused
    if getElementEditValues(furn, 'Record Header\record flags\Power Armor') <> '1' then exit;
    
    items := elementByPath(furn, 'Items');
    if not assigned(items) then exit; //if it's an empty frame, skip it

    if not isFurnFiltered(furn, filter_eval_furn) then exit;

    addMessage('***** Evaluating '+ getFileName(getFile(MasterOrSelf(furn))) + ' - ' + EditorID(furn) + ' '+ IntToHex(GetLoadOrderFormID(furn), 8) + ' *****');
    
    for i := 0 to elementCount(items)-1 do begin
        lvli := linksTo(ElementByPath(elementByIndex(items, i), 'CNTO\Item'));
        logg(1, 'Examining ' + editorId(lvli));
        if containsText(editorId(lvli), 'fusioncore') then continue;//skip analysis of fusion cores
        
        //If a lvli is already flagged for patching, then false 
        if getFileName(getFile(lvli)) = getFileName(mxPatchFile) then exit; 
        
        //If a lvli already has a faction keyword, then false
        if hasFactionKeyword(lvli) then exit;
        
    end;

    //then it's either for a faction based on it's name, OR it's eligable for default/epic status
    result := true;
end;

//============================================================================
procedure processFurn(furn: IInterface);
var
    countFact, furnFaction, countSet, countList: integer;
    items, defaultLvli, lvli, firstItem, secondItem, paintjob, newList, entries, listItems, addItem, listEntry: IInterface;
    faction, paSets: TStringList;
begin
    addMessage('***** Processing '+ EditorID(furn) + ' '+ IntToHex(GetLoadOrderFormID(furn), 8) + ' *****');
    furnFaction := -1;

    items := elementByPath(furn, 'Items');
    if not assigned(items) then raise Exception.Create('**ERROR** failed to assign items');
    firstItem := elementByPath(elementByIndex(items, 0), 'CNTO\Item');
    if not assigned(firstItem) then raise Exception.Create('**ERROR** failed to assign first item');
    secondItem := elementByPath(elementByIndex(items, 1), 'CNTO\Item');
    if (elementCount(items) > 1) AND (not assigned(secondItem)) then raise Exception.Create('**ERROR** failed to assign second item');

    //Look at the items - if individual pieces instead of suit, copy to lvli
        //create a new armor set list that has those individual pieces, replace in items
        //else grab the existing set lvli
    if (elementCount(items) > 2) then lvli := copyFurnToNewLvli(furn) 
    else if (elementCount(items) = 2) AND containsText(editorId(linksTo(firstItem)), 'fusionCore') then lvli := linksTo(secondItem)
    else if elementCount(items) = 2 then lvli := linksTo(firstItem)
    else if elementCount(items) = 1 then lvli := linksTo(firstItem)
    else raise Exception.Create('**ERROR** trying to process FURN with empty items');
    
    if signature(lvli) <> 'LVLI' then exit;

    //If based on the name, this is a faction pa suit, (but the levelled lists aren't faction specific)
    for countFact := 0 to listFactions.count-1 do begin
        if isFurnFiltered(furn, listFactions.objects[countFact].objects[fact_filter_lvli]) then faction := listFactions.objects[countFact]
        else if isLvliFiltered(lvli, listFactions.objects[countFact].objects[fact_filter_lvli]) then faction := listFactions.objects[countFact];
        if assigned(faction) then begin
            logg(3, 'Found faction PA Set: ' + editorId(furn));
            break;
        end;
    end;

    if assigned(faction) then begin
        if (getFileName(getFile(lvli)) = getFileName(mxPatchFile)) then addFilterKeywordToLVLI(lvli, faction[fact_kywd])
        //create a faction copy of the set list, replace it in the items
        else begin
            lvli := wbCopyElementToFile(lvli, mxPatchFile, true, true);
            setElementEditValues(lvli, 'EDID', editorId(lvli) + '_' + faction[fact_name]);
            addFilterKeywordToLVLI(lvli, faction[fact_kywd]);
            
            if containsText(editorId(linksTo(firstItem)), 'fusionCore') 
                    then setEditValue(secondItem, IntToHex(GetLoadOrderFormID(lvli), 8))
                    else setEditValue(firstItem, IntToHex(GetLoadOrderFormID(lvli), 8));
        end;
    end
    //ELSE if it is a default set
    else begin
        //iterate PA default paintjobs
        
        if winningRefByCount(furn) > 1 then paSets := listDefaultPaSets else paSets := listEpicPaSets;
        
        for countSet := 0 to paSets.count-1 do begin
            faction := paSets.objects[countSet];
            if not isLvliCompatible(lvli, faction) then continue;

            //lazy creation of a wrapper lvli and assign to the furn (so I don't do this if there's nothing compatible)
            if not assigned(defaultLvli) then begin
                defaultLvli := wbCopyElementToFile(template_pa_lvli, mxPatchFile, true, true);
                setElementEditValues(defaultLvli, 'EDID', 'LL_' + EditorId(furn));
                setElementEditValues(defaultLvli, 'LVLF\Use All', '0');
                
                //set the original LVLI as the first entry in the wrapper
                entries := elementByPath(defaultLvli, 'Leveled List Entries');
                setEditValue(elementByPath(elementByIndex(entries, 0), 'LVLO\Item'), IntToHex(GetLoadOrderFormID(lvli), 8));
                
                //assign the wrapper to then FURN
                if containsText(editorId(linksTo(firstItem)), 'fusionCore') 
                    then setEditValue(secondItem, IntToHex(GetLoadOrderFormID(defaultLvli), 8))
                    else setEditValue(firstItem, IntToHex(GetLoadOrderFormID(defaultLvli), 8));

                listItems := elementByPath(defaultLvli, 'Leveled List Entries');
            end;

            //create a copy of the list with the filter keyword
            newList := wbCopyElementToFile(lvli, mxPatchFile, true, true);
            setElementEditValues(newList, 'EDID', editorId(newList) + '_' + paSets[countSet]);
            
            addFilterKeywordToLVLI(newList, faction[fact_kywd]);
            
            addItem := elementByPath(ElementAssign(listItems, HighInteger, nil, false), 'LVLO');       
            SetEditValue(ElementByPath(addItem, 'Item'), IntToHex(GetLoadOrderFormID(newList), 8));
            setElementEditValues(addItem, 'Level', '1');
            setElementEditValues(addItem, 'Count', '1');

        end;
    end;
end;
//============================================================================
function copyFurnToNewLvli(furn: IInterface): IInterface;
var
    countFact, furnFaction, countItem, i: integer;
    items, newList, listItems, addItem, item, lvlo: IInterface;
begin
    logg(2, 'Creating Furn-Specific LVLI for ' + editorid(furn));
    newList := wbCopyElementToFile(template_pa_lvli, mxPatchFile, true, true);
    if not assigned(newList) then raise Exception.Create('**ERROR** Failed to copy template to new record');
    SetElementEditValues(newList, 'EDID', StringReplace(editorId(newList), 'template', editorId(furn), [rfReplaceAll, rfIgnoreCase]));
    listItems := elementByPath(newList, 'Leveled List Entries');
    if not assigned(listItems) then raise Exception.Create('**ERROR** listItems not assigned');
    
    //cut-paste the items from the FURN to the new levelled list
    items := elementByPath(furn, 'Items');
    for countItem := elementCount(items)-1 downTo 0 do begin
        //add a new item to the new levelled list (or use the first entry)
        logg(1, 'Copying entry ' + intToStr(countItem));
        if not assigned(addItem) then
            addItem := elementByIndex(listItems, 0)
        else 
            addItem := ElementAssign(listItems, HighInteger, nil, false);

        if not assigned(addItem) then raise Exception.Create('**ERROR** addItem not assigned');

        //copy the old item from the FURN\Items to the new levelled list entry addItem
        item := linksTo(ElementByPath(elementByIndex(items, countItem), 'CNTO\Item'));
        if not assigned(item) then raise Exception.Create('**ERROR** to get item');
        logg(1, 'Copying item from FURN ' + EditorId(item));
        lvlo := elementByPath(addItem, 'LVLO');
        if not assigned(lvlo) then raise Exception.Create('**ERROR** lvlo not assigned');
        SetEditValue(ElementByPath(lvlo, 'Item'), IntToHex(GetLoadOrderFormID(item), 8));
        setElementEditValues(lvlo, 'Level', '1');
        setElementEditValues(lvlo, 'Count', '1');

        //if it's not the last item, remove it, otherwise set it to the new levelled list
        if (countItem > 0) then RemoveByIndex(elementByPath(furn, 'Items'), countItem, true)
        else SetEditValue(ElementByPath(ElementByIndex(items, countItem), 'CNTO\Item'), IntToHex(GetLoadOrderFormID(newList), 8));

    end;
    result := newList;
end;
//============================================================================
function isLvliCompatible(rec: IInterface; faction: TStringList): boolean;
var    
    entries, ap, paintKeywords: IInterface;
    i, countAp, countMnams: integer;
    listAppr_listMnams_listPaintjobs, listMnams_listPaintjobs, cacheItemKwdaFormId: TStringList;
    sig: string;

begin
    result := false;
    if not assigned(faction) then raise exception.create('Missing Faction');
    sig := signature(rec);
    if sig = 'LVLI' then begin
        entries := elementByPath(rec, 'Leveled List Entries');
        //if any levelled list isn't compatible, return false
        for i := 0 to elementCount(entries)-1 do 
            if NOT isLvliCompatible(linksTo(elementByPath(elementByIndex(entries, i), 'LVLO\Item')), faction) 
                then exit;
                
        result := true;
        logg(1, 'Found compatible: ' + editorId(rec) + ' - ' + Faction[fact_name]);
        exit;
    end
    else if (sig = 'ARMO') or (sig = 'WEAP') then begin
        try
            cacheItemKwdaFormId := getKwdaCache(rec);
            listAppr_listMnams_listPaintjobs := faction.objects[fact_paintjobs];
            for countAp := 0 to listAppr_listMnams_listPaintjobs.count-1 do begin
                listMnams_listPaintjobs := listAppr_listMnams_listPaintjobs.objects[countAp];
                
                //grab the AP from the first paintjob in the first list- because it's sorted by AP they're all the same after this
                ap := linksTo(elementByPath(ObjectToElement(listMnams_listPaintjobs.objects[0].objects[0]), 'DATA\Attach Point'));
                
                //if it doesn't have the AP, then exit early false
                if not hasAp(rec, editorId(ap)) then continue;
                
                //for each combo of mnams
                for countMnams := 0 to listMnams_listPaintjobs.count-1 do begin
                
                    //For each paintjob keyword, check if the item has it, if it doesnt, then exit false
                    paintKeywords := ElementByPath(objectToElement(listMnams_listPaintjobs.objects[countMnams]), 'MNAM');
                    for i := 0 to ElementCount(paintKeywords)-1 do 
                        if not cacheContains(cacheItemKwdaFormId, linksTo(elementByIndex(paintKeywords, i)))
                            then exit;
                end;
            end;
        finally
            cacheItemKwdaFormId.free;
        end;
    end
    else logg(1, 'Skipping compatibility check for unrecognized sig: ' + signature(rec));
end;
//============================================================================
function HasAp(r: IInterface; keyword: string): boolean;
var
  i, j: integer;
  apprs: IwbElement;
  ap: String;
  templates, includes, omod: IInterface;

begin
    Result := false;
    //check the base APs
    apprs :=  ElementByPath(r, 'APPR');
    if apprs <> nil then for i := 0 to ElementCount(apprs)-1 do begin
        ap :=EditorID(LinksTo(ElementByIndex(apprs, i)));
        if not ContainsText(ap, keyword) then continue;
        Result := true;
        exit;
    end;
    
    //check for APs on default templates
    templates := ElementByPath(r, 'Object Template\Combinations');
    includes := ElementByPath(ElementByIndex(templates, 0), 'OBTS\Includes'); //Only check the 0th template (default)
    if not assigned(includes) then exit;
    for i := 0 to ElementCount(includes) do begin
        omod := linksTo(elementByPath(elementByIndex(includes, i), 'mod'));
        if not assigned(omod) then continue; 
    
        apprs :=  ElementByPath(omod, 'DATA\Attach Parent Slots');
        if apprs <> nil then for j := 0 to ElementCount(apprs)-1 do begin
            ap := EditorID(LinksTo(ElementByIndex(apprs, j)));
            if not ContainsText(ap, keyword) then continue;
            Result := true;
            exit;
        end;
    end;    
  
end;

end.