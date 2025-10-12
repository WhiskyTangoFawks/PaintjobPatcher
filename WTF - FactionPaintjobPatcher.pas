unit FactionPaintjobPatcher;

uses 'lib\mxpf';

var
    config : TMemIniFile;
    masterList, factions, nonFactionLists, defaultFaction, epicFaction, defaultPaSets, epicPaSets : TStringList;
    template_keyword, template_modcol, template_pa_lvli : IInterface;
    fact_name, fact_kywd, fact_alt_kywds, fact_paintjobs, fact_filter_paint, fact_filter_lvli : integer;

const	
    masterPlugin = fileByName('FactionPaintjobs.esp');
    log_level = 1; //1=trace, 2=debug, 3=info, 4=warn, 5=error

function Initialize: Integer;
var
  i: integer;
    slMasters: TStringList;
  
begin
    if not assigned(masterPlugin) then raise Exception.Create('**ERROR** Failed to find FactionPaintjobs.esp');
    
    // set MXPF options and initialize it
    DefaultOptionsMXPF;
    InitializeMXPF;
    
    template_keyword := MainRecordByEditorID(GroupBySignature(masterPlugin, 'KYWD'), 'if_tmp_Template_Restricted');
    template_modcol := MainRecordByEditorID(GroupBySignature(masterPlugin, 'OMOD'), 'modcol_template');
    template_pa_lvli := MainRecordByEditorID(GroupBySignature(masterPlugin, 'LVLI'), 'LL_Armor_Power_Set_Template');
    
    //SetExclusions('Fallout4.esm,DLCCoast.esm,DLCRobot.esm,DLCNukaWorld.esm,DLCWorkshop01.esm,DLCWorkshop02.esm,DLCWorkshop03.esm');
    
    // select/create a new patch file that will be identified by its author field
    PatchFileByAuthor('FactionPaintjobPatcher');
    
    slMasters := TStringList.Create;
    slMasters.Add('FactionPaintjobs.esp');
    AddMastersToFile(mxPatchFile, slMasters, False);
    
    //Initialize the faction config file;
    initConfigFiles();

    //Load the paintjobs, and copy Paintjobs to patch, so we can then filter COBJs by checking if the CNAM is in the patch
    LoadRecords('OMOD');
    AddMessage('Processing OMODs to index Paint Jobs');
    for i := MaxRecordIndex downto 0 do if (signature(GetRecord(i)) = 'OMOD') then if (NOT evalOmod(GetRecord(i))) then removeRecord(i);
    CopyRecordsToPatch;
    
    //Load COBJs, and remove it the CNAM isn't in the patch
    LoadRecords('COBJ');
    for i := MaxRecordIndex downto 0 do 
        if (signature(GetRecord(i)) = 'COBJ') then if (getFileName(getFile(winningOverride(linksTo(elementByPath(GetRecord(i), 'CNAM'))))) <> getFileName(mxPatchFile)) 
        then removeRecord(i);
    
    
    //Load LVLIs to the patch and copy, so we can then filter FURNs if the LVLI is already in the patch;
    LoadRecords('LVLI');
    AddMessage('Evaluating Lvli');
    for i := MaxRecordIndex downto 0 do if (signature(GetRecord(i)) = 'LVLI') then if (NOT evalLVLI(GetRecord(i))) then removeRecord(i);
    // then copy records to the patch file, so when evaluating FURN I know if target LVLIs are already flagged for patching
    CopyRecordsToPatch;
    
    //LoadRecords('ARMO');
    //LoadRecords('WEAP');
    LoadRecords('FURN');
    AddMessage('Evaluating Lvli, Cobj, Weap, and ARMOs for patching');
    for i := MaxRecordIndex downto 0 do if (getElementEditValues(getRecord(i), 'Record Header\record flags\Non-Playable') = '1') then removeRecord(i);
    for i := MaxRecordIndex downto 0 do if (signature(getRecord(i)) = 'ARMO') then if (NOT evalItem(getRecord(i))) then removeRecord(i);
    for i := MaxRecordIndex downto 0 do if (signature(getRecord(i)) = 'WEAP') then if (NOT evalItem(getRecord(i))) then removeRecord(i);
    for i := MaxRecordIndex downto 0 do if (signature(getRecord(i)) = 'FURN') then if (NOT evalFurn(getRecord(i))) then removeRecord(i);

    
    // then copy records to the patch file
    CopyRecordsToPatch;
    
   //*Process records
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'COBJ') then processCOBJ(GetPatchRecord(i));
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'LVLI') then processLVLI(GetPatchRecord(i));
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'ARMO') then processItem(GetPatchRecord(i));
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'WEAP') then processItem(GetPatchRecord(i));

    //Process furniture after PA has been processed, so any missing keywords are already added
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'FURN') then processFURN(GetPatchRecord(i));
    
end;
//
  //============================================================================
function Finalize: integer;
var
    i: integer;
begin
	logg(1, 'Finalizing');
    //TODO - reenable
    //for i := 0 to MaxPatchRecordIndex do removeIdenticalToMaster(GetPatchRecord(i));
    CleanMasters(mxPatchFile);
    PrintMXPFReport;
    FinalizeMXPF;
    
    config.free;
    for i := 0 to masterlist.count-1 do 
        for j := 0 to masterList.objects[i].count-1 do 
            masterList.objects[i].objects[j].free;
    
    masterList.free;

end;
//============================================================================
function evalOmod(omod: IInterface): boolean;
var
    newKeyword: IInterface;
    i, countMaster: integer;
    master, faction: TStringList;
    
begin
    result := false;
    //exit if it's not a paintjob
    if not getElementEditValues(omod, 'Record Header\record flags\Mod Collection') = '1' then exit;
    if not isOmodCraftable(omod) then exit;
    if not isPaintJob(omod) then exit;
    result := true;
    //TODO - figure out loadRecord(COBJ) for a specific record so I don't have to filter COBJ again when I already know which ones I want

    for countMaster := 0 to masterList.count -1 do begin
        master := masterList.objects[countMaster];
        for i := 0 to master.count -1 do begin
            faction := master.objects[i];
            if isFiltered(omod, faction.objects[fact_filter_paint]) then begin
                faction.objects[fact_paintjobs].addObject(IntToHex(GetLoadOrderFormID(omod), 8), omod);
                logg(3, 'Found Paintjob ' + editorId(omod) + ' for faction ' +masterList[countMaster] + ' - ' + master[i]);
            end;
        end;
    end;

    
end;
//============================================================================
function evalLVLI(lvli: IInterface): boolean;
var
    i, j: integer;
    faction : TStringList;
begin
    result := false;
    if (winningRefByCount(lvli) < 1) then exit; //skip unused levelled lists
    if hasFactionKeyword(lvli) then exit; //If a lvli already has a filter keyword, skip it
    
    //If the editorID contains one of the faction search terms, then flag it for patching.
    for i := 0 to factions.count-1 do begin
        faction := factions.objects[i];
        result := isFiltered(lvli, faction.objects[fact_filter_lvli]);
        if (result) then exit;
    end;
    
end;

//============================================================================
function evalItem(item: IInterface): boolean;
var
    sig: string;
    countFaction, countmaster, countPaintjobs: integer;
    master, faction, paintjobs: TStringList;
    paintjob : IInterface;
    
begin
    //filter out non playable and unused
    result := false;
    if (getElementEditValues(item, 'Record Header\record flags\Non-Playable') = '1') then exit; //skip unplayable items
    if (winningRefByCount(item) < 1) then exit; //skip unused items

    sig := signature(item);
    
    addMessage('***** Evaluating '+ EditorID(item) + ' '+ IntToHex(GetLoadOrderFormID(item), 8) + ' *****');
    //true exit conditions
    result := true;
    
    //if it has the standard paint APs
    if hasPaintjobAP(item) then exit;
    
    //Check for a compatible paint job
    for countMaster := 0 to masterList.count -1 do begin
        master := masterList.objects[countMaster];
        for countFaction := 0 to master.count-1 do begin
            faction := master.objects[countFaction];
            paintjobs := faction.objects[fact_paintjobs];
            for countPaintjobs := 0 to paintjobs.count-1 do begin
                paintJob := ObjectToElement(paintJobs.objects[countPaintjobs]);
                if isPaintjobCompatibleKeyword(paintjob, item) then exit;
                if isPaintjobCompatibleMatswap(paintjob, item) then exit;
            end;
        end;
    end;

    //if no match, the false
    result := false;    
end;

//============================================================================
function processLVLI(lvli: IInterface): boolean;
var
    i : integer;
    filters, entry: IInterface;
    faction: TStringList;
begin
    addMessage('***** Processing '+ EditorID(lvli) + ' '+ IntToHex(GetLoadOrderFormID(lvli), 8) + ' *****');
    //If the editorID contains one of the faction search terms, then flag it for patching.
    for i := 0 to factions.count-1 do begin
        faction := factions.objects[i];
        //skip to next if
        if not isFiltered(lvli, faction.objects[fact_filter_lvli]) then continue;
        addFilterKeywordToLVLI(lvli, faction[fact_kywd]);
        exit;
    end;
end;
//============================================================================
function processItem(item: IInterface): boolean;
var
    
    modcols, skipFactions, master, faction, paintjobs, factionModcols, defaultModcols: TStringList;
    paintJob, entry, ap, mnam, template, templates, listKwds, newKeyword, listmods, addmod, modID, flag, addIndex, oldentry, faction_ap_modcol, temp: IInterface;
    modcolEdid, sig: string;
    isCompatible, hasFactionTemplates : boolean;
    i, countPaintjob, countFaction, countFilter, countTemplate, countMaster, countAP, countModcol, api, addonIndex, countPaintjobs, indexAp, factionIndex, indexDefault, indexEpic : integer;

begin
    addMessage('***** Processing '+ EditorID(item) + ' '+ IntToHex(GetLoadOrderFormID(item), 8) + ' *****');
    sig := signature(item);
    skipFactions := TStringList.create;
    hasFactionTemplates := generateFactionTemplate(item);
    modcols := TStringList.create; //map<faction, map<AP, modcol>>, modcols are item specific

    templates := ElementByPath(item, 'Object Template\Combinations');

    //iterate paintjobs
    //Build the paintjob modcols, and add missing keywords
    for countMaster := 0 to masterList.count -1 do begin
        master := masterList.objects[countMaster];
        for countFaction := 0 to master.count-1 do begin
            faction := master.objects[countFaction];
            paintjobs := faction.objects[fact_paintjobs];
            
            //skip faction modcol generation if it's a faction (not default or epic) the item already has a template for it
            logg(1, 'checking ' + faction[fact_name]);
            if (faction[fact_name] <> 'Default') AND (faction[fact_name] <> 'Epic') and itemAlreadyHasTemplatesForFaction(item, faction) then continue;
            
            factionModcols := TStringList.create;
            
            //todo - filter item based on faction -> continue
            if (paintjobs.count = 0) then logg(1, 'No paintjobs found for ' + faction[fact_name]);
            for countPaintjobs := 0 to paintjobs.count-1 do begin
                paintJob := ObjectToElement(paintJobs.objects[countPaintjobs]);
                isCompatible := false;
                ap := linksTo(elementByPath(paintjob, 'DATA\Attach Point'));
                //grab the paintjob specific keyword from the filter keywords
                mnam := getPainjobMnam(paintjob);
                logg(1, 'evaluating paintjob: ' + editorId(paintjob) + ' AP: ' + editorId(ap) + ' Generic Paint MNAM: ' + editorId(mnam));

                //Build paintjob modcols: check for compatibility, by keywords then by matSwap
                if isPaintjobCompatibleKeyword(paintJob, item) then isCompatible := true
                else if isPaintjobCompatibleMatswap(paintJob, item) then begin
                    if isGenericPaintKeyword(mnam) then begin
                        logg(3, 'Adding missing keyword:AP :    ' + editorId(mnam) + ':' + editorId(ap));
                        isCompatible := true;//check if it's a known generic paintjob keyword
                        addMissingKywdAp(mnam, ap, item);
                    end else logg(4, 'SKIPPING: Found compatible mat swap, but unrecognized material keyword: ' + editorId(mnam));
                end;
                if not isCompatible then continue;
                //Add to Modcols
                
                //get or generate new modcol
                indexAP := factionModcols.indexOf(editorId(ap));
                if (indexAP < 0) then begin
                    logg(2, 'Generating faction modcol for ' + faction[fact_name] +  '_' + editorId(ap));
                    modcolEdid := 'modcol_'+ editorId(item) + '_' + editorId(mnam) + '_' + editorId(ap) + '_' + faction[fact_name];
                    faction_ap_modcol := wbCopyElementToFile(template_modcol, mxPatchFile, true, true);
                    factionModcols.addObject(editorId(ap), faction_ap_modcol);
                    indexAP := factionModcols.count-1;
                    SetElementEditValues(faction_ap_modcol, 'EDID', modcolEdid);
                    SetEditValue(ElementByPath(faction_ap_modcol, 'DATA\Attach Point'), IntToHex(GetLoadOrderFormID(ap), 8));
                end else faction_ap_modcol := factionModcols.objects[indexAp];
                
                //add the paintjob to the modcol
                if isFiltered(paintjob, faction.objects[fact_filter_paint]) then begin
                    logg(2, 'Found Paintjob: ' + editorId(paintjob) + ' for faction ' + faction[fact_name] + ' on AP ' + editorId(ap));
                    entry := ElementAssign(ElementByPath(faction_ap_modcol, 'DATA\Includes'), HighInteger, nil, False);
                    setElementEditValues(entry, 'Mod', IntToHex(GetLoadOrderFormID(paintjob), 8));
                end;
            end;
            //if any modcols were created, then store the list for addition to items, otherwise discard
            if (factionModcols.count > 0) then modcols.addObject(faction[fact_name], factionModcols) else factionModcols.free;
        end;    
    end;

    //add faction modcols to weap/armo
    //iterate through the templates
    indexEpic := modcols.indexOf('Epic');
    for countTemplate := 0 to ElementCount(templates)-1 do Begin
		logg(1, editorId(item) + ' - Examining template ' + IntToStr(countTemplate));
		oldentry := ElementByIndex(templates, countTemplate);
		addonIndex := StrToInt(GetElementEditValues(oldentry, 'OBTS\Parent Combination Index'));
        
        //If it's a basic template, ie not already has a qualifier like faction
        if addonIndex = -1 then begin
			logg(1, 'Found basic template');
			
            //add the default modcol standard templates
			indexDefault := modcols.indexOf('Default');
            if indexDefault > -1 then begin
                defaultModcols := modcols.objects[indexDefault];
                for countAP := 0 to defaultModcols.count-1 do begin 
                    addModcolToExistingTemplate(oldentry, ObjectToElement(defaultModcols.objects[countAp]));
                end;
            end;
    
			//if it's clothing, only do default TODO (and maybe add epic too?)
			if hasFactionTemplates then continue;
            
            //here we iterate through the generated modcols keywords, and generate templates for each
            for countModcol := 0 to modcols.count-1 do begin
                factionName := modcols[countModcol];
                if (factionName = 'Default') or (factionName = 'Epic') then continue;
                faction := getFaction(factionName);
                generateFactionVersionOfTemplate(item, faction, modcols.objects[countModcol], countTemplate);
			end;
		end
        else begin //(else) it's a template based on a pre-existing template
            logg(1, 'Found pre-existing non-default template ' + IntToStr(countTemplate));
			//if it's epic, add epic, otherwise do nothing
            if getLoadOrderFormId(LinksTo(elementByIndex(ElementByPath(oldentry, 'OBTS\Keywords'), 0))) = getLoadOrderFormId(ObjectToElement(epicFaction.objects[fact_kywd])) 
            AND (indexEpic > -1) then begin
                for countAP := 0 to modcols.objects[indexEpic].count-1 do begin 
                    addModcolToExistingTemplate(oldentry, ObjectToElement(modcols.objects[indexEpic].objects[countAp]));
                end;
            end;
		end;

	end;
    for i := 0 to modcols.count-1 do modcols.objects[i].free;
    modcols.free;
end;

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
    
    //skip specific suits
    if containsText(editorId(furn), 'abraxo') then exit;
    if containsText(editorId(furn), 'sugar') then exit;
    if containsText(editorId(furn), 'danse') then exit;
    if containsText(editorId(furn), 'armorvim') then exit;
    if containsText(editorId(furn), 'nukacola') then exit;
    if containsText(editorId(furn), 'quantum') then exit;
    if containsText(editorId(furn), 'tesla') then exit;
    if containsText(editorId(furn), 'decap') then exit;
    if containsText(editorId(furn), 'NoStealCore') then exit; //Proctor Ingram

    for i := 0 to elementCount(items)-1 do begin
        lvli := linksTo(ElementByPath(elementByIndex(items, i), 'CNTO\Item'));
        logg(1, 'Examining ' + editorId(lvli));
        if containsText(editorId(lvli), 'fusioncore') then continue;//skip analysis of fusion cores
        
        //If a lvli is already flagged for patching, skip it 
        if getFileName(getFile(lvli)) = getFileName(mxPatchFile) then exit; 
        
        //If a lvli is already has a faction keyword, then skip it
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

    logg(1, '1st item= ' +editorId(linksTo(firstItem)));
    logg(1, '2nd item= ' +editorId(linksTo(secondItem)));

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
    for countFact := 0 to factions.count-1 do begin
        if isFiltered(furn,  factions.objects[countFact].objects[fact_filter_lvli]) OR isFiltered(lvli,  factions.objects[countFact].objects[fact_filter_lvli]) then begin
            faction := factions.objects[countFact];
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
        end;
    end
    //ELSE if it is a default set
    else begin
        //iterate PA default paintjobs
        
        if winningRefByCount(furn) > 1 then paSets := defaultPaSets else paSets := epicPaSets;
        
        for countSet := 0 to paSets.count-1 do begin
            //If list isn't compatible, skip it
            if not isPaintjobListCompatibleKeyword(paSets.objects[countSet].objects[fact_paintjobs], lvli) then continue;
            
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
            faction := paSets.objects[countSet];
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
function processCOBJ(cobj: IInterface): boolean;
var
    i : integer;
begin
    //TODO - process cobj
    //Painjobs are processed by OMOD, I should probably handle OMOD from COBJ and do it as a pair
        //That way, I have access to the faction results for the paintjob
end;

//============================================================================
// Configuration
//============================================================================

procedure initConfigFiles();
var
  i, j, p : integer;
  keywordString, filename : String;
  keyword : IInterface;
  configFactions, factionValues, filterValues, temp : TStringList;

const
    ini_kywd = 'keyword';
    ini_alt_keywords = 'alt_keywords';
    ini_filterItemType = 'filter_item_type';
    ini_isDefaultPA  = 'is_default_pa';
    ini_isEpicPa = 'is_epic_pa';
    ini_filter_lvli = 'filter_lvli';
    ini_filter_paint = 'filter_paintjob';   

begin
    logg(1, 'Loading Config Ini');
    config := TMemIniFile.Create('Edit Scripts\FactionPaintjobs\Factions.ini');
    factions := TStringList.create;
    defaultPaSets := TStringList.create;
    epicPaSets := TStringList.create;
    configFactions := TStringList.create;
    config.readSections(configFactions);
    //iterate the configured factions
    for i := 0 to configFactions.count-1 do begin
        logg(1, 'Loading faction config: ' + configFactions[i]);
        //todo - if is default/epic Power Armor configuration, store seperately
        
        //If this is the default or epic, assign it to their standalone variable, else add it to the factions list
        factionValues := TStringList.create;
        if (configFactions[i] = 'Default') then defaultFaction := factionValues
        else if (configFactions[i] = 'Epic') then epicFaction := factionValues
        else if(config.readString(configFactions[i], ini_isDefaultPA, '') = 'true') then defaultPaSets.addObject(configFactions[i], factionValues)
        else if(config.readString(configFactions[i], ini_isEpicPA, '') = 'true') then epicPaSets.addObject(configFactions[i], factionValues)
        else factions.addObject(configFactions[i], factionValues);

        
        //index 0, Faction Name
        fact_name := 0;
        factionValues.addObject(configFactions[i], configFactions[i]);

        //index 1, the formID for the keyword
        fact_kywd := 1;
        keyword := generateFactionKeyword(configFactions[i], config.readString(configFactions[i], ini_kywd, ''));
        factionValues.addObject(intToHex(GetLoadOrderFormID(keyword), 8), keyword);

        //index 2, alt keywords
        //load formID + IINterface into the tstringlist
        fact_alt_kywds := 2;
        temp := getConfigList(configFactions[i], ini_alt_keywords);
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
        factionValues.addObject(ini_filter_paint, getConfigList(configFactions[i], ini_filter_paint));
        
        //index 5, the lvli filter
        fact_filter_lvli := 5;
        factionValues.addObject(ini_filter_lvli, getConfigList(configFactions[i], ini_filter_lvli));

        //index, item filter

    end;
    logg(3, intToStr(configFactions.count) + ' Configurations loaded');
    logg(3, intToStr(defaultPaSets.count) + ' Default PA Sets loaded');
    logg(3, intToStr(epicPaSets.count) + ' Epic PA Sets loaded');
    if assigned(defaultFaction) then logg(3, 'Default Faction Loaded') else logg(4, 'Missing default faction');
    if assigned(epicFaction) then logg(3, 'Epic Faction Loaded') else logg(4, 'Missing epic faction');
    configFactions.free;

    nonFactionLists := TStringList.create;
    nonFactionLists.addObject('default', defaultFaction);
    nonFactionLists.addObject('epic', epicFaction);
    
    masterList := TStringList.create;
    masterList.addObject('non-factions', nonFactionLists);
    masterList.addObject('factions', factions);
    masterList.addObject('default_pa', defaultPaSets);
    masterList.addObject('epic_pa', epicPaSets);

end;


//=======
function generateFactionKeyword(faction, keyword: String): IInterface;
var
    p : integer;
    filename : String;
    newKeyword : IInterface;

begin
    //get the override keyword, if present, eg: fallout4.esm|if_tmp_atomcats
    if (keyword <> '') then begin
        p := Pos('|', keyword);
        filename := Copy(keyword, 1, p-1);
        keyword := Copy(keyword, P+1, Length(keyword));
        result :=MainRecordByEditorID(GroupBySignature(fileByName(filename), 'KYWD'), keyword);
        if not assigned(result) then raise Exception.create('** ERROR ** unable to find keyword ' + keyword + ' in file ' + filename);
        logg(1, 'Found override keyword: ' + filename + '|' + keyword + ' : ' + editorId(result));
    end
    //else create the faction keyword
    else begin
        newKeyword := wbCopyElementToFile(template_keyword, mxPatchFile, true, true);
        setElementEditValues(newKeyword, 'EDID', 'if_tmp_' + faction);
        result := newKeyword;
        logg(1, 'Generated faction keyword ' + editorId(newKeyword));
    end;
end;

//=======
function getConfigList(faction, key: String): TStringList;
var
    str: String;

begin
    str := config.readString(faction, key, '');
    str := StringReplace(str, ' ', '', [rfReplaceAll, rfIgnoreCase]);
    
    result := TStringList.create;
    result.Delimiter := ',';
    result.DelimitedText := str;
    if (result.count < 1) then logg(4, 'Found empty faction filter: ' + faction + ' - ' +key);
end;
//=======
function getFaction(factionName: String): TStringList;
var
    i, factIndex: Integer
begin
    for i: 0 to masterList.count-1 do begin
        factIndex := masterlist.objects[i].indexOf(factionName);
        if (i > 0) then result := factions.objects[i];
        if assigned(result) then exit;
    end;
    raise exception.create('**ERROR** Unable to find registered faction: ' + factionName);
end;
//============================================================================  
function isFiltered(rec: IInterface; filterList: TStringList): boolean;
var
    countFilter: integer;
    prefix, filterString: String;
begin
    result := false;
    
    if not assigned(rec) then raise exception.create('**ERROR** Missing record');
    if not assigned(filterList) then raise exception.create('**ERROR** Missing filter list');

    //iterate through the filter terms
    for countFilter := 0 to filterList.count-1 do begin

        prefix := Copy(filterList[countFilter], 1, 1);
        if (prefix = '+') or (prefix = '-') or (prefix = '!') then begin
            filterString := Copy(filterList[countFilter], 2, Length(filterList[countFilter]) - 1);
        end else begin
            prefix := '';
            filterString := filterList[countFilter];
        end;
        
        if (prefix = '+') then begin
            //requires: if a rec DOESN'T have this, return false and exit
            if not (containsText(editorId(rec), filterString) 
            OR containsText(getElementEditValues(rec, 'FULL'), filterString)) then begin
                result := false;
                exit;
            end;
        end else if (prefix = '-') then begin
            //Blacklist: If a rec has this, return false and exit
            if (containsText(editorId(rec), filterString) 
            OR containsText(getElementEditValues(rec, 'FULL'), filterString)) then begin
                result := false;
                exit;
            end;
        end else if (prefix = '') then begin
            //no prefix: terminal entry. If the rec has this filter keyword, then return true and exit
            if containsText(editorId(rec), filterString) 
            OR containsText(getElementEditValues(rec, 'FULL'), filterString) then begin
                logg(2, 'rec meets filter criteria: ' + editorId(rec));
                result := true;
                exit;
            end;
        end else raise Exception.Create('**ERROR** encountered unexpected filter prefix: ' + filterList[countFilter]);
    end;
    //logg(1, 'rec fails filter criteria: ' + editorId(rec));
    result := false;
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
        for countFaction := 0 to factions.count-1 do begin
            //check base keyword
            faction := factions.objects[countFaction];
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
            
            //Check for Epic
            if GetLoadOrderFormID(keyword) = GetLoadOrderFormID(ObjectToElement(epicFaction.objects[fact_kywd])) then begin
                result := true;
                exit;
            end;
            
        end;
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
    keyword := ObjectToElement(faction.objects[fact_kywd]);
    if getFileName(getFile(keyword)) <> getFileName(masterPlugin) then begin
        logg(1, 'checking if ' + editorId(item) + ' references ' + editorId(keyword));
        for i := 0 to ReferencedByCount(keyword) -1 do begin
            refBy := ReferencedByIndex(keyword, i);
            if (getLoadOrderFormId(refBy) = getLoadOrderFormId(item)) AND isWinningOverride(refBy) then begin
                logg(2, 'found ' + faction[fact_name] + 'template with kywd ' + editorId(keyword) + ' on ' + editorId(item));
                exit;
            end;
        end;
    end;
    
    for countAlt := 0 to faction.objects[fact_alt_kywds].count-1 do begin
        keyword := ObjectToElement(faction.objects[fact_alt_kywds].objects[countAlt]);
        if getFileName(getFile(keyword)) <> getFileName(masterPlugin) then begin
            logg(1, 'checking if ' + editorId(item) + ' references ' + editorId(keyword));
            for i := 0 to ReferencedByCount(keyword)-1 do begin
                refBy := ReferencedByIndex(keyword, i);
                if (getLoadOrderFormId(refBy) = getLoadOrderFormId(item)) AND isWinningOverride(refBy) then begin
                    logg(2, 'found ' + faction[fact_name] + 'template with kywd ' + editorId(keyword) + ' on ' + editorId(item));
                    exit;
                end;
            end;
        end;
    end;
end;

//============================================================================
// Utility
//============================================================================
function isOmodCraftable(omod: IInterface): boolean;
var
    temp: IInterface;
    i: integer;

begin
    //refby omods, detect paint jobs
    result := false;
    for i := 0 to ReferencedByCount(omod)-1 do begin
        temp := ReferencedByIndex(omod, i);
        if not isWinningOverride(temp) then continue;
        if signature(temp) = 'COBJ' then begin
            result := true;
            exit;
        end;
    end;
end;
//============================================================================
function addFilterKeywordToLVLI(lvli: IInterface; keywordFormId: String): boolean;
var
    filters, entry: IInterface;

begin
    logg(1, 'Adding filter keyword ' + keywordFormId + ' to ' + editorId(lvli));
    if not assigned(keywordFormId) OR (keywordFormId = '') then raise exception.create('**ERROR** - addFilterKeywordToLVLI called without a keyword form id');
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
function hasKwda(e: IInterface; edid: string): boolean;
var
  kwda: IInterface;
  n: integer;
begin
  Result := false;
  kwda := ElementByPath(e, 'Keywords\KWDA');
  if not assigned(kwda) then Exception.Create('**ERROR** failed to get keywords from ' + editorId(e));
  for n := 0 to ElementCount(kwda) - 1 do begin
    if editorId(LinksTo(ElementByIndex(kwda, n))) = edid then begin 
      Result := true;
      exit;
    end;
  end;
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

//============================================================================
function isPaintJob(omod: IInterface): boolean;
var
    ap : string;
    i: integer;
    refBy, properties : IInterface;
    hasMatSwap : boolean;
begin
    //TODO - eventually need more robust examination of this
        //Could add a check on the omod for a matswap
    result := false;
    hasMatSwap := false;
    ap := getElementEditValues(omod, 'DATA\Attach Point');
    if ContainsText(ap, 'ap_WeaponMaterial') then result := true;
    if ContainsText(ap, 'Paint') then result := true;
    if ContainsText(ap, 'color') then result := true;

    properties := ElementByPath(omod, 'DATA\Properties');
    for i := 0 to ElementCount(properties)-1 do begin
        if getElementEditValues(ElementByIndex(properties, i), 'Property') <> 'MaterialSwaps' then continue;
        hasMatSwap := true;
        break;
    end;
    if not hasMatSwap then exit;
        
    //Check refBy, if it's already assigned to a weapon, or already in a modcol, then we don't want to redistribute it
    for i := 0 to ReferencedByCount(omod)-1 do begin
        refBy := ReferencedByIndex(omod, i);
        if not isWinningOverride(refBy) then continue;
        if (signature(refBy) = 'WEAP') OR (signature(refBy) = 'OMOD') OR (signature(refBy) = 'ARMO') then begin
            result := false;
            exit;
        end;
    end;
     
end;

//============================================================================

function normalizeMat(s: String): String;

begin
    result := lowerCase(s);
    result := StringReplace(result, ' ', '', [rfReplaceAll, rfIgnoreCase]);
    result := StringReplace(result, 'materials\', '', [rfReplaceAll, rfIgnoreCase]);
    result := StringReplace(result, '.BGSM', '', [rfReplaceAll, rfIgnoreCase]);
        
end;
//============================================================================
function getReplacedMaterialsForPaintJob(paintjob: IInterface): TStringList;
var
    properties, matswap, substitutions: IInterface;
    i, j: integer;
begin
    if not assigned(paintjob) then raise Exception.Create('**ERROR** getReplacedMaterialsForPaintjob called with null');
    result := TStringList.create;
    properties := ElementByPath(paintjob, 'DATA\Properties');
    //check the paintjob matswaps
    //logg(1, EditorId(Paintjob) + ' ' + intToStr(ElementCount(properties)) + ' properties on omod');
    for i := 0 to ElementCount(properties)-1 do begin
        if getElementEditValues(ElementByIndex(properties, i), 'Property') <> 'MaterialSwaps' then continue;
        matswap := LinksTo(ElementByPath(ElementByIndex(properties, i), 'Value 1'));
        substitutions := ElementByPath(matswap, 'Material Substitutions');
        //logg(1, EditorId(matSwap) + ' matswap ' + intToStr(ElementCount(substitutions)) + ' substitutions');
        for j := 0 to ElementCount(substitutions)-1 do begin
            result.add(normalizeMat(getElementEditValues(elementByIndex(substitutions, j), 'BNAM')));
        end;
    end;
    //logg(1, EditorId(paintjob) + ' materials replaced = ' + intToStr(result.count));
end;
//============================================================================
function getMaterials(item: IInterface): TStringList;
var
    objMaterials, templates, includes, omod: IInterface;
    i, j: integer;
    sig: string;
    
begin
    result := TStringList.create;
    
    sig := signature(item);
    if sig = 'ARMO' then begin
        objMaterials := elementByPath(item, 'Male\World Model\MO2T\Materials');
    end
    else if sig = 'WEAP' then begin
        objMaterials := elementByPath(item, '1st Person Model\MO4T\Materials');
        
    end
    else raise Exception.Create('**ERROR** unhandled signature: ' + sig);
    
    for i := 0 to elementCount(objMaterials)-1 do 
        result.add(normalizeMat(GetElementValues(elementByIndex(objMaterials, i), 'Folder Hash') +  '\' +  GetElementValues(elementByIndex(objMaterials, i), 'File Hash')));
    
    //check the default template for added compatible things
    templates := ElementByPath(item, 'Object Template\Combinations');
    includes := ElementByPath(ElementByIndex(templates, 1), 'OBTS\Includes');
    for i := 0 to ElementCount(includes) do begin
        omod := linksTo(elementByPath(elementByIndex(includes, i), 'mod'));
        objMaterials := elementByPath(omod, 'Model\MODT\Materials');

        for j := 0 to elementCount(objMaterials)-1 do 
            result.add(normalizeMat(GetElementValues(elementByIndex(objMaterials, j), 'Folder Hash') +  '\' +  GetElementValues(elementByIndex(objMaterials, j), 'File Hash')));
    end;
    //logg(1, 'Found materials count ' + intToStr(result.count));
end;

//============================================================================
function hasPaintjobAP(item: IInterface): boolean;
var
    sig: string;    

begin
    result := false;
    
    sig := signature(item);
    if sig = 'ARMO' then begin
        if hasAP(item, 'ap_armor_Paint') OR hasAP(item, 'ap_PowerArmor_Paint') then begin
            result := true;
            //logg(1, 'Found paintjob AP on  ' + editorId(item));
            exit;
        end;
    end
    else if sig = 'WEAP' then begin
        if hasAP(item, 'ap_WeaponMaterial') then begin //TODO - not sure AP_WeaponMAterial isn't used extensively on melee weapons
            result := true;
            //logg(1, 'Found paintjob AP on  ' + editorId(item));
            exit;
        end;
    end
    else raise Exception.Create('**ERROR** unhandled signature: ' + sig);
        
end;

//============================================================================
function isPaintjobCompatibleKeyword(paintjob, item: IInterface): boolean;
var
    mnam, ap: string;
    i : integer;
    entries : IInterface;
begin
    result := false;
    
    if signature(item) = 'LVLI' then begin
        entries := elementByPath(item, 'Leveled List Entries');
        for i := 0 to elementCount(entries)-1 do 
            if NOT isPaintjobCompatibleKeyword(paintjob, linksTo(elementByPath(elementByIndex(entries, i), 'LVLO\Item'))) then exit;
        result := true;
        exit;
    end;

    //check if the thing has the correct keyword and ap
    ap := editorId(linksTo(elementByPath(paintjob, 'DATA\Attach Point')));
    
    if not hasAP(item, ap) then exit;

    for i := 0 to elementCount(ElementByPath(paintjob, 'MNAM'))-1 do begin
        mnam := editorId(LinksTo(ElementByIndex(ElementByPath(paintjob, 'MNAM'), i)));
        if mnam = '' then raise exception.create('**ERROR** failed to assign MNAM');
        if not hasKwda(item, mnam) then exit;
    end;

    logg(2, 'Found Paintjob with matching keywords ' + editorId(Paintjob) +  ' - ' + EditorId(item));
    result := true;
    
end;
//============================================================================
function isPaintjobListCompatibleKeyword(paintjobs: TStringList; item: IInterface): boolean;
var
    i : integer;
    entries : IInterface;
begin
    result := false;
    if signature(item) = 'LVLI' then begin
        entries := elementByPath(item, 'Leveled List Entries');
        //if any levelled list isn't compatible, return false
        for i := 0 to elementCount(entries)-1 do 
            if NOT isPaintjobListCompatibleKeyword(paintjobs, linksTo(elementByPath(elementByIndex(entries, i), 'LVLO\Item'))) then begin
                result := false;
                exit;
            end;
        result := true;
        exit;
    end
    else if (signature(item) = 'ARMO') or (signature(item) = 'WEAP') then begin
        for i := 0 to paintjobs.count-1 do begin
            //if any paintjob is compatible, then return true
            if isPaintjobCompatibleKeyword(ObjectToElement(paintjobs.objects[i]), item) then begin
                result := true;
                exit;
            end;
        end;
        result := false;
    end
    else logg(1, 'Skipping compatibility check for unrecognized sig: ' + signature(item));
    
    
end;
//============================================================================
//checks against all paintjobs in the list, if an item or every terminal item of a lvli has a compatible paintjob
function hasCompatiblePaintjob(paintjobs: TStringList; item: IInterface): TStringList;
var
    mnam, ap: string;
    i : integer;
    entries : IInterface;
begin
    for i := 0 to paintjobs.count-1 do begin
        paintjob := ObjectToElement(paintjobs.objects[i]);
        result := isPaintjobCompatibleKeyword(paintjob, item);
        if result then exit;
    end;
end;
//============================================================================
function isPaintjobCompatibleMatswap(paintjob, Item: IInterface): TStringList;
var
    paintjobMats, mats : TStringList;
    i, j: integer;
    mnam, ap: string;
    

begin
    result := false;
    
    mats := getMaterials(item);
    paintjobMats := getReplacedMaterialsForPaintJob(paintjob);
    for i := 0 to paintJobMats.Count -1 do begin
        for j := 0 to mats.count -1 do begin
            //logg(1, 'comparing ' + mats[j] + ' == ' + paintJobMats[i]);
            if (mats[j] <> paintJobMats[i]) then continue;
            result := true;
            logg(2, 'Found Paintjob by matching matswap on ' + editorId(item) + ' ' + editorId(paintjob));
            exit;
        end;
    end;
    mats.free;
    paintjobMats.free;

end;

//============================================================================
procedure addMissingKywdAp(mnam, ap, item: IInterface);
var
   entry: IInterface;

begin
    //add keywords if missing
    if not hasKwda(item, editorID(mnam)) then begin
        Logg(2, 'Adding keyword ' + editorId(mnam) + ' to ' + editorId(item));
        entry := ElementAssign(ElementByPath(item, 'Keywords\KWDA'), HighInteger, nil, False);
        setEditValue(entry, IntToHex(GetLoadOrderFormID(mnam), 8));
    end;
    if not hasAP(item, editorID(ap)) then begin
        Logg(2, 'Adding Attachment Point ' + editorId(mnam) + ' to ' + editorId(ap));
        entry := ElementAssign(ElementByPath(item, 'APPR'), HighInteger, nil, False);
        setEditValue(entry, IntToHex(GetLoadOrderFormID(ap), 8));
    end;

end;

//============================================================================  
procedure addModcolToExistingTemplate(entry, modcol: IInterface);
var
  i: integer;
  omod, addmod, flag, includes: IInterface;

begin
    //If there's an omod with a compatible AP, then go ahead and replace it
    includes := ElementByPath(entry, 'OBTS\Includes');
    if not assigned(includes) then raise Exception.Create('**ERROR** includes not assigned ');
    for i := 0 to ElementCount(includes)-1 do begin
        omod := winningOverride(linksTo(elementByPath(elementByIndex(includes, i), 'Mod')));
        
        //check that the APs match
        if getElementEditValues(omod, 'DATA\Attach Point') <> getElementEditValues(modcol, 'DATA\Attach Point') then continue;
        //if the omod has any properties, then stop iterating, we only want to replace "null" omods
        if assigned(elementByPath(omod, 'DATA\Includes')) then break;
        
        SetEditValue(ElementByPath(elementByIndex(includes, i), 'Mod'), IntToHex(GetLoadOrderFormID(modcol), 8));
        logg(1, 'Replaced ' + editorId(omod) + ' -> ' + editorId(modcol));
        exit;
    end;
    
    //else add the omod as a new includes
    addmod := ElementAssign(includes, HighInteger, nil, False);
	SetEditValue(ElementByPath(addmod, 'Mod'), IntToHex(GetLoadOrderFormID(modcol), 8));
	flag := ElementByPath(addmod, 'Don''t Use All');
	SetEditValue(flag, 'True');
    logg(1, 'Added as new ' + editorId(modcol));
  
end;

//============================================================================  
procedure generateFactionVersionOfTemplate(item: IInterface; faction, modcols: TStringList; parentIndex: integer);
var
    entry, newKeyword, listmods, addmod, modID, modcol : IInterface;
    i: integer;
begin
   //Add faction copies of this template for each registered faction modcol
    	
    //create the new template
    entry := ElementAssign(ElementByPath(item, 'Object Template\Combinations'), HighInteger, nil, False);
    setElementEditValues(entry, 'FULL', faction[fact_name]);
    
    newKeyword := ElementAssign(ElementByPath(entry, 'OBTS\Keywords'), HighInteger, nil, False);
    SetEditValue(newKeyword, faction[fact_kywd]);
    SetElementEditValues(entry, 'OBTS\Parent Combination Index', parentIndex); 
    
    //iterate through the attachment points, adding the fact mods for all the attachment points to the template for the faction
    for i := 0 to modcols.count-1 do Begin
        listmods := ElementByPath(entry, 'OBTS\Includes');
        addmod := ElementAssign(listmods, HighInteger, nil, False);
        modID := ElementByPath(addmod, 'Mod');

        logg(1, 'adding modcol : ' + modcols[i]);
        SetEditValue(modID, modcols[i]);
    
        SetEditValue(ElementByPath(addmod, 'Don''t Use All'), 'True');
    end;
end;
//============================================================================
function isGenericPaintKeyword(mnam: IInterface): boolean;
var
  listMods : IInterface;
  i : Integer;
begin
    result := false;
    if ContainsText(editorId(mnam), 'paint') then result := true
    else if ContainsText(editorId(mnam), 'material') then result := true
    else if ContainsText(editorId(mnam), 'color') then result := true;
end;
//============================================================================
function getPainjobMnam(paintjob: IInterface): IInterface;
var
  temp : IInterface;
  i : Integer;
begin
    for i := 0 to elementCount(ElementBySignature(paintjob, 'MNAM'))-1 do begin
        temp := ElementByIndex(ElementBySignature(paintjob, 'MNAM'), i);
        logg(1, 'Evaluating keyword as candidate for generic: ' + 'editorId(temp)');
        if isGenericPaintKeyword(temp) then begin
            result := temp;
            exit;
        end;
    end;
end;
//============================================================================
function generateFactionTemplate(item: IInterface): integer;
var
  i, countFaction: integer;
  keywords: IwbElement;
begin
    if hasKwda(item, 'ObjectTypeWeapon') then result := true
    else if hasKwda(item, 'ObjectTypeArmor') then result := true
    else if hasKwda(item, 'ArmorTypePower') then result := true
    else result := false;
end;
//============================================================================
function winningRefByCount(e: IInterface): integer;
var
    i: integer;

begin
    result := 0;
    for i := 0 to ReferencedByCount(e)-1 do begin
        if isWinningOverride(ReferencedByIndex(e, i)) then result := result + 1;
    end;
      
end;

//============================================================================  
// log
procedure logg(msg_level: integer; msg: string);
var
  prefix: string;

begin
    if msg_level = 1 then prefix := 'TRACE- '
    else if msg_level = 2 then prefix := 'DEBUG- '
    else if msg_level = 3 then prefix := 'INFO- '
    else if msg_level = 4 then prefix := 'WARN- '
    else if msg_level = 5 then prefix := 'ERROR- ';

    if log_level <= msg_level then addMessage(prefix + msg);
    
end;

//============================================================================
function removeIdenticalToMaster(e: IInterface): integer;
var
  m, prevovr, ovr: IInterface;
  i: integer;
begin
  logg(1, 'Checking for identical to master: ' + Name(e));
  m := MasterOrSelf(e);

  // find previous override record in a list of overrides for master record
  prevovr := m;
  for i := 0 to Pred(OverrideCount(m)) do begin
    ovr := OverrideByIndex(m, i);
    if Equals(ovr, e) then
      Break;
    prevovr := ovr;
  end;
  
  // remove record if no conflicts
  if ConflictAllForElements(prevovr, e, False, False) <= caNoConflict then begin
     logg(1, 'Removing: ' + Name(e));
    remove(e);
  end;
end;

//===
end.
