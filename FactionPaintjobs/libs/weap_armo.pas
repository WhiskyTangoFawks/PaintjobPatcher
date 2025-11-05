unit FPD_weap_armo;

//============================================================================
procedure processItem(item: IInterface);
var
    faction, listApprModcol, cacheApprFormId, cacheKywdFormId: TStringList;
    countFaction: integer;

begin
    if (getElementEditValues(item, 'Record Header\record flags\Non-Playable') = '1') then exit; //skip unplayable items
    if assigned(elementByPath(item, 'CNAM')) then exit; //templated weapons
    if assigned(elementByPath(item, 'TNAM')) then exit; //templated armor
    if (winningRefByCount(item) < 1) then exit; //skip unused items
    
    cacheApprFormId := getApprCache(item);
    cacheKywdFormId := getKwdaCache(item);
    if not isItemFiltered(item, filter_eval_item, cacheApprFormId, cacheKywdFormId) then exit;

    addMessage('***** Processing '+ getFileName(getFile(MasterOrSelf(item))) + ' ' + EditorID(item) + ' '+ IntToHex(GetLoadOrderFormID(item), 8) + ' *****');
    
    item := addMissingKeywords(item, cacheApprFormId, cacheKywdFormId);
    if not assigned(ElementByPath(item, 'APPR')) then begin 
        logg(1, 'No APPR path found, skipping');
        exit;
    end;
    if not assigned(ElementByPath(item, 'Keywords\KWDA')) then begin
        logg(1, 'No Keywords\KWDA path found, skipping');
        exit;
    end;
    if not hasCompatiblePaintjob(item, cacheApprFormId, cacheKywdFormId) then exit;
    
    item := copyOverrideToPatch(item);
    
    if not assigned(ElementByPath(item, 'Object Template\Combinations')) then addDefaultTemplate(item);

    //TODO - remove "color" words from armor Names, and fix names that include a '|' or '-'

    //generate Default, and apply
    faction := getItemDefaultFaction(item, cacheApprFormId, cacheKywdFormId);
    if assigned(faction) then begin 
        logg(1, 'Processing Default Templates');
        listApprModcol := buildFactionModcols(item, cacheApprFormId, cacheKywdFormId, faction);
        applyDefaultModcols(item, faction, listApprModcol);
        listApprModcol.free;
    end
    else logg(4, 'No default faction found for ' + editorId(item));
    
    //generate Epic, and apply
    faction := getItemEpicFaction(item, cacheApprFormId, cacheKywdFormId);
    if assigned(faction) then begin 
        logg(1, 'Processing Epic Templates');
        listApprModcol := buildFactionModcols(item, cacheApprFormId, cacheKywdFormId, faction);
        applyFactionModcols(item, faction, listApprModcol);
        listApprModcol.free;
    end
    else logg(4, 'No epic faction found for ' + editorId(item));
    
    //generate Standard Factions, and apply
    for countFaction := 0 to listFactions.count-1 do begin
        faction := listFactions.objects[countFaction];
        if not isItemFiltered(item, faction.objects[fact_filter_item], cacheApprFormId, cacheKywdFormId) then begin
            logg(1, 'Failed faction item filter, skipping: ' + faction[fact_name]);
            continue;
        end;
        logg(1, 'Processing Faction Templates: ' + faction[fact_name]);
        listApprModcol := buildFactionModcols(item, cacheApprFormId, cacheKywdFormId, faction);
        applyFactionModcols(item, faction, listApprModcol);
        listApprModcol.free;
    end;
    
    if (cacheKywdFormId.indexOf(pa_kwd_hex) > -1) then begin
        //generate Default PA Sets, and apply
        for countFaction := 0 to listDefaultPaSets.count-1 do begin
            faction := listDefaultPaSets.objects[countFaction];
            if not isItemFiltered(item, faction.objects[fact_filter_item], cacheApprFormId, cacheKywdFormId) then continue
            logg(1, 'Processing Default PA Set Template: ' + faction[fact_name]);
            listApprModcol := buildFactionModcols(item, cacheApprFormId, cacheKywdFormId, faction);
            applyFactionModcols(item, faction, listApprModcol);
            listApprModcol.free;
        end;
        //generate Epic PA Sets, and apply
        for countFaction := 0 to listEpicPaSets.count-1 do begin
            faction := listEpicPaSets.objects[countFaction];
            if not isItemFiltered(item, faction.objects[fact_filter_item], cacheApprFormId, cacheKywdFormId) then continue
            logg(1, 'Processing Epic PA Set Template: ' + faction[fact_name]);
            listApprModcol := buildFactionModcols(item, cacheAppr, cacheKywdFormId, faction);
            applyFactionModcols(item, faction, listApprModcol);
            listApprModcol.free;
        end;
    end;

    cacheApprFormId.free;
    cacheKywdFormId.free;
    
end;
//=============================
function hasCompatiblePaintjob(item : IInterface; cacheApprFormId, cacheKywdFormId: TStringList):boolean;
var
    countFaction, countAp, countMnams: integer;
    listAppr_listMnams_listPaintjobs, listMnams_listPaintjobs, listPaintjobs :TStringList;
    ap, paintjob: IInterface;
    apEdid: String;
begin
    result := false;
    for countFaction := 0 to listMaster.count()-1 do begin
        listAppr_listMnams_listPaintjobs := listMaster.objects[countFaction].objects[fact_paintjobs];
        for countAp := 0 to listAppr_listMnams_listPaintjobs.count-1 do begin
            listMnams_listPaintjobs := listAppr_listMnams_listPaintjobs.objects[countAp];
            //grab the AP from the first paintjob in teh first list- because it's sorted by AP they're all the same after this
            ap := linksTo(elementByPath(ObjectToElement(listMnams_listPaintjobs.objects[0].objects[0]), 'DATA\Attach Point'));
            apEdid := editorId(ap);
            
            for countMnams := 0 to listMnams_listPaintjobs.count-1 do begin
                listPaintjobs := listMnams_listPaintjobs.objects[countMnams];
                paintjob := ObjectToElement(listPaintjobs.objects[0]);

                if isPaintjobCompatibleKeyword(paintjob, cacheApprFormId, cacheKywdFormId) then begin
                    result := true;
                    exit;
                end;
            end;
        end;
    end;
    logg(1, 'No compatible patinjobs found');
end;

//=============================
procedure addDefaultTemplate(item: IInterface);
var
    temp, combos, firstCombo: IInterface;
begin
    logg(2, 'Adding default template to item without any templates');
    
    temp := Add(item, 'Object Template', True);
    combos := ElementAssign(temp, 1, nil, False);
    firstCombo := ElementByIndex(combos, 0);
    
    setElementEditValues(firstCombo, 'FULL', 'Default');
    setElementEditValues(firstCombo, 'OBTS\Default', 'True');
    setElementEditValues(firstCombo, 'OBTS\Parent Combination Index', '-1')
end;

//============================================================================
procedure applyDefaultModcols(item: IInterface; faction, listApprModcol: TStringList);
var
    countTemplate, countAp, parentIndex: integer;
    templates, template, modcol: IInterface;
begin
    if (listApprModcol.count = 0) then begin
        logg(1, 'applyDefaultModcols: listApprModcol.count = 0');
        exit;
    end;
    
    templates := ElementByPath(item, 'Object Template\Combinations');
    for countTemplate := 0 to ElementCount(templates)-1 do Begin
		template := ElementByIndex(templates, countTemplate);
		parentIndex := StrToInt(GetElementEditValues(template, 'OBTS\Parent Combination Index'));
        
        if (parentIndex <> -1) then exit;  //once we hit non-standard templates, we can stop iterating
		
        for countAp := 0 to listApprModcol.count-1 do begin 
            modcol := ObjectToElement(listApprModcol.objects[countAp]);
            addModcolToExistingTemplate(template, modcol);
        end;
    end;
            
end;

//============================================================================
procedure applyFactionModcols(item: IInterface; faction, listApprModcol: TStringList);
var
    countTemplate, countAlt, countAp, parentIndex, maxTemplate: integer;
    templates, template: IInterface;
    kwdaFormId : cardinal;
    hasFactionTemplate : boolean;
begin
    if (listApprModcol.count = 0) then begin
        logg(1, 'applyFactionModcols called with empty modcol list');
        exit;
    end;
    logg(1, 'Applying faction modcols: ' + faction[fact_name]);
    //if already has faction, then enrich, ELSE create version for each default
    hasFactionTemplate := false;
    templates := ElementByPath(item, 'Object Template\Combinations');
    if not assigned(templates) then raise exception.create('Failed to assign templates');
    for countTemplate := 0 to ElementCount(templates)-1 do Begin
        template := ElementByIndex(templates, countTemplate);
        kwdaFormId := GetLoadOrderFormID(linksTo(elementByIndex(ElementByPath(template, 'OBTS\Keywords'), 0)));
        
        //check main keyword
        if kwdaFormId = getLoadOrderFormId(objectToElement(faction.objects[fact_kywd])) then begin
            hasFactionTemplate := true;
            for countAp := 0 to listApprModcol.count-1 do addModcolToExistingTemplate(template, objectToElement(listApprModcol.objects[countAp]));            
        end;
        //check alt keywords
        for countAlt := 0 to faction.objects[fact_alt_kywds].count-1 do begin
            if kwdaFormId = getLoadOrderFormId(ObjectToElement(faction.objects[fact_alt_kywds].objects[countAlt])) then begin
                hasFactionTemplate := true;
                for countAp := 0 to listApprModcol.count-1 do addModcolToExistingTemplate(template, objectToElement(listApprModcol.objects[countAp]));            
            end;
        end;
    end;
		
    if hasFactionTemplate then begin
        logg(1, 'Item already has faction: ' + faction[fact_name]);
        exit;
    end;
    
    maxTemplate := ElementCount(templates);
    logg(1, 'Generating Faction Template Versions for ' + intToStr(maxTemplate) + ' parent templates');
    for countTemplate := 0 to maxTemplate-1 do Begin
        logg(1, ' generating faction version of ' + intToStr(countTemplate));
        template := ElementByIndex(templates, countTemplate);
        parentIndex := StrToInt(GetElementEditValues(template, 'OBTS\Parent Combination Index'));
        if (parentIndex <> -1) then exit; //If we've hit the non-basic templates, then we're done.
        generateFactionVersionOfTemplate(item, faction, listApprModcol, countTemplate);
    end;
            
end;

//============================================================================  
procedure generateFactionVersionOfTemplate(item: IInterface; faction, listApprModcol: TStringList; parentIndex: integer);
var
    entry, newKeyword, listmods, addmod, modID, modcol : IInterface;
    i: integer;
begin
    //Add faction copies of this template for each registered faction modcol
    logg(1, 'Generating faction version of template for ' + faction[fact_name] + ' with modlist count ' + intToStr(listApprModcol.count));
    //create the new template
    entry := ElementAssign(ElementByPath(item, 'Object Template\Combinations'), HighInteger, nil, False);
    newKeyword := ElementAssign(ElementByPath(entry, 'OBTS\Keywords'), HighInteger, nil, False);
    setElementEditValues(entry, 'OBTS\Parent Combination Index', parentIndex); 
    setEditValue(newKeyword, faction[fact_kywd]);
    setElementEditValues(entry, 'FULL', faction[fact_name]);
    listmods := ElementByPath(entry, 'OBTS\Includes');

    //iterate through the attachment points, adding the fact mods for all the attachment points to the template for the faction
    for i := 0 to listApprModcol.count-1 do Begin
        addmod := ElementAssign(listmods, HighInteger, nil, False);
        modID := ElementByPath(addmod, 'Mod');
        modcol := ObjectToElement(listApprModcol.objects[i]);
        logg(1, 'adding modcol : ' + editorId(modcol));
        
        SetEditValue(modID, IntToHex(getLoadOrderFormId(modcol), 8));
        SetEditValue(ElementByPath(addmod, 'Don''t Use All'), 'True');
    end;
end;

//============================================================================
//Accepts an item, the pre-built caches for it, and a faction. Returns a list of modcols of compatible paintjobs for the given faction.
function buildFactionModcols(item: IInterface; cacheApprFormId, cacheKywdFormId, faction: TStringList): TStringList;
var
    listAppr_listMnams_listPaintjobs, listMnams_listPaintjobs: TStringList;
    listPaintjobsForAp, listMnams, listPaintjobs: TStringList;
    ap, paintjob, mnam, mnams, modcol, entry, omod: IInterface;
    countAp, countMnams, countMnam, paintjobCount, i: Integer;
    apEdid, modcolEdid: string;
    isCompatible: Boolean;

begin
    result := TStringList.create;
    listAppr_listMnams_listPaintjobs := faction.objects[fact_paintjobs];
    logg(1, 'building faction modcols for ' + faction[fact_name]);
    for countAp := 0 to listAppr_listMnams_listPaintjobs.count-1 do begin
        listMnams_listPaintjobs := listAppr_listMnams_listPaintjobs.objects[countAp];
        //grab the AP from the first paintjob in teh first list- because it's sorted by AP they're all the same after this
        ap := linksTo(elementByPath(ObjectToElement(listMnams_listPaintjobs.objects[0].objects[0]), 'DATA\Attach Point'));
        apEdid := editorId(ap);
        
        //use a temporary list to hold compatible paintjobs, and another list of MNAMs that need to be added
        //The mnam list is used later, to create the modcolEdid, so I don't have to iterate the the compatible paintjobs again to collect the MNAMs
        listPaintjobsForAp := TStringList.create;
        listMnams := TStringList.create;
        listMnams.Duplicates := dupIgnore;
        listMnams.sorted := true;
        listMnams.Delimiter := '-';
        
        //for each mnam combo, add if it's compatible add the painjobs
        for countMnams := 0 to listMnams_listPaintjobs.count-1 do begin
            listPaintjobs := listMnams_listPaintjobs.objects[countMnams];
            paintjob := ObjectToElement(listPaintjobs.objects[0]);
            
            //check for AP, use isCompatible to track is-compatible-so-far
            isCompatible := cacheContains(cacheApprFormId, ap);
            
            //Check the mnams
            if isCompatible then for i := 0 to elementCount(ElementByPath(paintjob, 'MNAM'))-1 do begin
                mnam := LinksTo(ElementByIndex(ElementByPath(paintjob, 'MNAM'), i));
                if not cacheContains(cacheKywdFormId, mnam) then begin
                    isCompatible := false;
                    break;
                end;
            end;
            
            //If this paintjoblist isn't compatible then skip to the next paintjoblist
            if not isCompatible then continue;
            
            //add all teh paintjobs to the temp list
            listPaintjobsForAp.addStrings(listPaintjobs);
            //add all the mnams to the mnam list
            mnams := ElementByPath(paintjob, 'MNAM');
            for countMnam := 0 to elementCount(mnams)-1 do
                listMnams.add(editorId(LinksTo(ElementByIndex(mnams, countMnam))));
                
        end;

        //If there were any compatible paintjobs for this AP, create the modcol
        if (listPaintjobsForAp.count > 0) then begin
            
            //Create the modcols
            modcolEdid := 'modcol_'+ '_' + apEdid + '-' + listMnams.DelimitedText + faction[fact_name];
            modcol := MainRecordByEditorID(GroupBySignature(patchFile, 'OMOD'), modcolEdid);
            
            //If the modcol already exists, then I don't need to do anything else, it's already correctly populated with the same filter output
            if assigned(modcol) then begin
                logg(1, 'Modcol already exists: ' + modcolEdid);
                
            end else begin //create it new
                modcol := copyRecordToFile(template_modcol, patchFile, true);
                SetElementEditValues(modcol, 'EDID', modcolEdid);
                SetElementEditValues(modcol, 'FULL', faction[fact_name]);
                SetEditValue(ElementByPath(modcol, 'DATA\Attach Point'), IntToHex(GetLoadOrderFormID(ap), 8));
                
                //add each paintjob to the modcol
                for paintjobCount := 0 to listPaintjobsForAp.count-1 do begin
                    paintjob := ObjectToElement(listPaintjobsForAp.objects[paintjobCount]);
                    if paintjobCount = 0 then entry := ElementByIndex(ElementByPath(modcol, 'DATA\Includes'), 0)
                    else entry := ElementAssign(ElementByPath(modcol, 'DATA\Includes'), HighInteger, nil, False);
                    setElementEditValues(entry, 'Mod', IntToHex(GetLoadOrderFormID(paintjob), 8));
                end;
                logg(1, 'Created modcol: ' + editorID(modcol));
            end;
        
            result.addObject(apEdid, modcol);
        end;
        listMnams.free;
        listPaintjobsForAp.free;
    end;
end;

//============================================================================
function concatMnams(omod:IInterface): String;
var
    listMnams : TStringList;
    mnam: string;
    i: integer;
    mnams: IInterface;
begin
    listMnams := TStringList.create;
    listMnams.sorted := true;
    listMnams.Delimiter := '-';
    listMnams.Duplicates := dupIgnore;

    mnams := ElementByPath(omod, 'MNAM');
    for i := 0 to elementCount(mnams)-1 do begin
        mnam := editorId(LinksTo(ElementByIndex(mnams, i)));
        listMnams.add(mnam);
    end;
    
    result := listMnams.DelimitedText;
    listMnams.Free;
    logg(1, 'ConcatMnams: ' + result);
end;

//============================================================================  
procedure addModcolToExistingTemplate(entry, modcol: IInterface);
var
  i: integer;
  modcolAp: cardinal;
  omod, addmod, flag, includes: IInterface;


begin
    logg(1, 'AddModcolToExistingTemplate: ' + editorId(modcol));

    //If there's an omod with a compatible AP, then go ahead and replace it
    includes := ElementByPath(entry, 'OBTS\Includes');
    if not assigned(includes) then raise Exception.Create('**ERROR** includes not assigned ');
    
    //for each omod/modcol on the template, check if it has the same AP as the modcol to add
    modcolAp := getLoadOrderFormId(LinksTo(ElementByPath(modcol, 'DATA\Attach Point')));
    for i := 0 to ElementCount(includes)-1 do begin
        omod := winningOverride(linksTo(elementByPath(elementByIndex(includes, i), 'Mod')));
        logg(1, 'AddModcolToExistingTemplate comparing ' + editorId(modcol) + ' and ' + editorId(omod));
        //if the AP matches the target modcol, either replace or exit
        if getLoadOrderFormId(LinksTo(ElementByPath(omod, 'DATA\Attach Point'))) = modcolAp then begin
            if modcolContainsOmod(modcol, omod) then begin
                SetEditValue(ElementByPath(elementByIndex(includes, i), 'Mod'), IntToHex(GetLoadOrderFormID(modcol), 8));
                logg(1, 'Replaced ' + editorId(omod) + ' -> ' + editorId(modcol));
            end;
            exit;
        end;
    end;
    
    //else add the omod as a new includes
    addmod := ElementAssign(includes, HighInteger, nil, False);
	SetEditValue(ElementByPath(addmod, 'Mod'), IntToHex(GetLoadOrderFormID(modcol), 8));
	flag := ElementByPath(addmod, 'Don''t Use All');
	SetEditValue(flag, 'True');
    logg(1, 'Added as new template ' + editorId(modcol));
  
end;

//============================================================================  
function getApprCache(item : IInterface): TStringList;
var
    i, j: integer;
    apprs: IwbElement;
    ap: String;
    templates, includes, omod: IInterface;

begin
    result := TStringList.create;
    result.Sorted := true;
    result.Duplicates := dupIgnore;
    
    apprs :=  ElementByPath(item, 'APPR');
    if apprs <> nil then 
        for i := 0 to ElementCount(apprs)-1 do result.add(IntToHex(getLoadOrderFormId(LinksTo(ElementByIndex(apprs, i))), 8));
    
    //check for APs on default templates
    templates := ElementByPath(item, 'Object Template\Combinations');
    includes := ElementByPath(ElementByIndex(templates, 0), 'OBTS\Includes'); //Only check the 0th template (default)
    if not assigned(includes) then exit;
    for i := 0 to ElementCount(includes)-1 do begin
        omod := linksTo(elementByPath(elementByIndex(includes, i), 'mod'));
        if not assigned(omod) then continue; 
    
        apprs :=  ElementByPath(omod, 'DATA\Attach Parent Slots');
        if apprs <> nil then 
            for j := 0 to ElementCount(apprs)-1 do 
                result.add(IntToHex(getLoadOrderFormId(LinksTo(ElementByIndex(apprs, j))), 8));
        
    end;
end;
//============================================================================  
function getKwdaCache(item: IInterface):TStringList;
var
  kwda: IInterface;
  n: integer;
begin
  
    result := TStringList.create;
    result.Sorted := true;
    result.Duplicates := dupIgnore;
    result.CaseSensitive := true; 
    
    kwda := ElementByPath(item, 'Keywords\KWDA');
    if not assigned(kwda) then begin
        logg(5, 'failed to get keywords from ' + editorId(item));
        exit;
    end;
    for n := 0 to ElementCount(kwda) - 1 do result.add(IntToHex(getLoadOrderFormId(LinksTo(ElementByIndex(kwda, n))), 8));
    
end;
//============================================================================  
function cacheContains(cache:TStringList; rec: IInterface): boolean;

begin
    result := (cache.indexOf(IntToHex(getLoadOrderFormId(rec), 8)) <> -1); 
end;


end.
