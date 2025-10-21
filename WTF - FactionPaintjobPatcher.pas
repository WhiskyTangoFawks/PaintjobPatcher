unit FactionPaintjobPatcher;

uses 'lib\mxpf';

var
    config_factions, config_options : TMemIniFile;
    listMaster, listFactions, listDefaultFactions, listEpicFactions, listDefaultPaSets, listEpicPaSets, filter_paintjob_ap, filter_paintjob_kywd, filter_allow_redistribute, filter_eval_furn, filter_eval_item, filter_eval_omod, filter_eval_lvli: TStringList;
    template_keyword, template_modcol, template_pa_lvli : IInterface;
    fact_name, fact_kywd, fact_alt_kywds, fact_paintjobs, fact_filter_paint, fact_filter_lvli, fact_filter_item : integer;
    epic_kywd_formId : cardinal;

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
    if not assigned(template_keyword) then raise Exception.create('** ERROR ** Failed to find template_keyword');
    
    template_modcol := MainRecordByEditorID(GroupBySignature(masterPlugin, 'OMOD'), 'modcol_template');
    if not assigned(template_modcol) then raise Exception.create('** ERROR ** Failed to find template_modcol');
    
    template_pa_lvli := MainRecordByEditorID(GroupBySignature(masterPlugin, 'LVLI'), 'LL_Armor_Power_Set_Template');
    if not assigned(template_pa_lvli) then raise Exception.create('** ERROR ** template_pa_lvli');
    
    epic_kywd_formId := GetLoadOrderFormID(MainRecordByEditorID(GroupBySignature(fileByName('Fallout4.esm'), 'KYWD'), 'if_Epic_Restricted'));
    

    
    //SetExclusions('Fallout4.esm,DLCCoast.esm,DLCRobot.esm,DLCNukaWorld.esm,DLCWorkshop01.esm,DLCWorkshop02.esm,DLCWorkshop03.esm');
    
    // select/create a new patch file that will be identified by its author field
    PatchFileByAuthor('FactionPaintjobPatcher');
    
    slMasters := TStringList.Create;
    slMasters.Add('FactionPaintjobs.esp');
    AddMastersToFile(mxPatchFile, slMasters, False);
    
    //Initialize the faction config file;
    initConfig();
    initFactions();
    

    //Load the paintjobs, and copy Paintjobs to patch, so we can then filter COBJs by checking if the CNAM is in the patch
    LoadRecords('OMOD');
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('** Evaluating OMODs as potential paintjobs **');
    for i := MaxRecordIndex downto 0 do if (signature(GetRecord(i)) = 'OMOD') then if (NOT evalOmod(GetRecord(i))) then removeRecord(i);
    CopyRecordsToPatch; //copy OMODs to patch, so we can eval COBJs based on omod presence
    
    //Load COBJs, and remove if the CNAM isn't in the patch
    LoadRecords('COBJ');
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('** Evaluating COBJs for paintjobs copied to patch **');
    for i := MaxRecordIndex downto 0 do if (signature(GetRecord(i)) = 'COBJ') then if (NOT evalCobj(GetRecord(i))) then removeRecord(i);   
    CopyRecordsToPatch; //copy COBJs to patch, so we can process omods/cobjs

    //*Process OMODs and COBJs first, so Paintjobs are Indexes
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Processing OMODS/COBJs');
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'COBJ') then processOmodAndCobj(GetPatchRecord(i));
    
    //Load LVLIs to the patch and copy, so we can then filter FURNs if the LVLI is already in the patch;
    LoadRecords('LVLI');
    AddMessage('Evaluating Lvli');
    for i := MaxRecordIndex downto 0 do if (signature(GetRecord(i)) = 'LVLI') then if (NOT evalLVLI(GetRecord(i))) then removeRecord(i);
    // then copy records to the patch file, so when evaluating FURN I know if target LVLIs are already flagged for patching
    CopyRecordsToPatch;

    //Process Remaining Records
    LoadRecords('ARMO');
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Evaluating ARMOs for patching');
    for i := MaxRecordIndex downto 0 do if (getElementEditValues(getRecord(i), 'Record Header\record flags\Non-Playable') = '1') then removeRecord(i);
    for i := MaxRecordIndex downto 0 do if (signature(getRecord(i)) = 'ARMO') then if (NOT evalItem(getRecord(i))) then removeRecord(i);
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Evaluating WEAPs for patching');
    LoadRecords('WEAP');
    for i := MaxRecordIndex downto 0 do if (signature(getRecord(i)) = 'WEAP') then if (NOT evalItem(getRecord(i))) then removeRecord(i);
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Evaluating FURNs for patching');
    LoadRecords('FURN');
    for i := MaxRecordIndex downto 0 do if (signature(getRecord(i)) = 'FURN') then if (NOT evalFurn(getRecord(i))) then removeRecord(i);

    
    // then copy records to the patch file
    CopyRecordsToPatch;
    

    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Processing LVLIs');
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'LVLI') then processLVLI(GetPatchRecord(i));
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Processing ARMOs');
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'ARMO') then processItem(GetPatchRecord(i));
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Processing WEAPs');
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'WEAP') then processItem(GetPatchRecord(i));
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Processing FURNs');
    //Process furniture after PA has been processed, so any missing keywords are already added
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'FURN') then processFURN(GetPatchRecord(i));
    
end;
//
  //============================================================================
function Finalize: integer;
var
    i: integer;
begin
	addMessage('   ');
    addMessage('   ');
    addMessage('** Finalizing Patch **');
    
    //TODO - reenable
    for i := 0 to MaxPatchRecordIndex do begin 
        if (signature(GetPatchRecord(i)) <> 'COBJ')  AND (ReferencedByCount(GetPatchRecord(i)) < 1) then logg(5, 'Found unreferenced patch record: ' + EditorID(GetPatchRecord(i)) + ' '+ IntToHex(GetLoadOrderFormID(GetPatchRecord(i)), 8) + ' *****');
        //removeIdenticalToMaster(GetPatchRecord(i)); //TODO - reenable
    end;
    CleanMasters(mxPatchFile);
    PrintMXPFReport;
    FinalizeMXPF;
    
    config_factions.free;
    config_options.free;
    for i := 0 to listMaster.count-1 do listMaster.objects[i].free;
    
    listMaster.free;
    listDefaultFactions.free;
    listDefaultPaSets.free;
    listEpicFactions.free;
    listEpicPaSets.free;
end;
//============================================================================
function evalOmod(omod: IInterface): boolean;
var
    properties, refBy: IInterface;
    i, j: integer;
    listFaction, faction: TStringList;
    prop: string;
    hasMatSwap: boolean;
    
    
begin
    result := false;
    //exit if it's not a paintjob
    if getElementEditValues(omod, 'Record Header\Record Flags\Mod Collection') = '1' then exit;
    if not isRecordFiltered(linksTo(elementByPath(omod, 'DATA\Attach Point')), filter_paintjob_ap) then exit;
    if not isRecordFiltered(omod, filter_eval_omod) then exit;

    addMessage('***** Evaluating Paintjob ' + getFileName(getFile(omod)) + ' - ' + EditorID(omod) + ' '+ IntToHex(GetLoadOrderFormID(omod), 8) + ' *****');
    if not isOmodCraftable(omod) then begin
        logg(2, 'Skipping uncraftable paintjob');
        exit;
    end;
    
    //If there are any properties, validate that it has a mat-swap or a color index
    if (elementCount(ElementByPath(omod, 'DATA\Properties')) > 0) then begin
        hasMatSwap := false;
        properties := ElementByPath(omod, 'DATA\Properties');
        for i := 0 to ElementCount(properties)-1 do begin
            prop := getElementEditValues(ElementByIndex(properties, i), 'Property');
            if (prop = 'MaterialSwaps') OR (prop = 'ColorRemappingIndex') then begin;
                hasMatSwap := true;
                break;
            end;
        end;
        if not hasMatSwap OR containsText(editorId(omod), 'default') then begin
            logg(2, 'Skipping paintjob without mapswap');
            exit;
        end;

        if not isRecordFiltered(omod, filter_allow_redistribute) then begin
            //Check refBy, if it's already assigned to a weapon, or already in a modcol, then we don't want to redistribute it
            for i := 0 to ReferencedByCount(omod)-1 do begin
                refBy := ReferencedByIndex(omod, i);
                if not isWinningOverride(refBy) then continue;
                if (signature(refBy) = 'WEAP') OR (signature(refBy) = 'ARMO') OR (signature(refBy) = 'QUST') OR (signature(refBy) = 'FLST') then begin
                    logg(3, 'Paintjob is already distributed, returning false: ' + editorId(omod));
                    result := false;
                    exit;
                end
                else if (signature(refBy) = 'OMOD') then begin
                    //TODO - I am not entirely sure what to do here, if the modcol isn't attached to anything it isn't valid
                    //And even if it is, then it's part of some sort of random distribution, so it's probably OK to include...
                end;
            end;
        end;
    end;
    
    result := true;
    
end;

//============================================================================
function evalCobj(cobj: IInterface): boolean;
var
    cnam : IInterface;

begin
    result := false;
    
    cnam := winningOverride(linksTo(elementByPath(cobj, 'CNAM')));
    if (getFileName(getFile(cnam)) <> getFileName(mxPatchFile)) then exit;
    //addMessage('***** Evaluating '+ getFileName(getFile(cobj)) + ' - ' + EditorID(cobj) + ' '+ IntToHex(GetLoadOrderFormID(cobj), 8) + ' *****');
    
    result := true;
end;

//============================================================================
procedure processOmodAndCobj(cobj: IInterface);
var
    omod: IInterface;
    i: integer;
    faction: TStringList;

begin
    omod := winningOverride(linksTo(elementByPath(cobj, 'CNAM')));
    addMessage('***** Processing Paintjob ' + getFileName(getFile(MasterOrSelf(omod))) + ' - ' + EditorID(omod) + ' '+ IntToHex(GetLoadOrderFormID(omod), 8) + ' *****');
    
    //Add the paintjob to the stored paintjob lists for the various factions
    for i := 0 to listMaster.count -1 do begin
        faction := listMaster.objects[i];
        logg(1, 'evaluating faction ' + faction[fact_name]);
        if isRecordFiltered(omod, faction.objects[fact_filter_paint]) then begin
            faction.objects[fact_paintjobs].addObject(IntToHex(GetLoadOrderFormID(omod), 8), omod);
            logg(3, 'FOUND MATCHING - Faction= ' + faction[fact_name] + ' paintjob= ' + editorId(omod));
        end 
        else logg(1, 'nonmatching: Faction= ' + faction[fact_name] + ' paintjob= ' + editorId(omod));
    
    end;

    //TODO - remove LNAM from OMOD configuration

    //TODO - process cobj
        //Crafting Recipe Standardization, Special Component?
        //Recipe Locking: Faction? Magazine?
    
end;

//============================================================================
function evalLVLI(lvli: IInterface): boolean;
var
    i: integer;
    faction : TStringList;
begin
    result := false;
    addMessage('***** Evaluating ' + getFileName(getFile(lvli)) + ' - ' + EditorID(lvli) + ' '+ IntToHex(GetLoadOrderFormID(lvli), 8) + ' *****');
    if (winningRefByCount(lvli) < 1) then exit; //skip unused levelled lists
    if hasFactionKeyword(lvli) then exit; //If a lvli already has a filter keyword, skip it
    if not isRecordFiltered(lvli, filter_eval_lvli) then exit;
    
    //If the editorID contains one of the faction search terms, then flag it for patching.
    for i := 0 to listFactions.count-1 do begin
        faction := listFactions.objects[i];
        result := isRecordFiltered(lvli, faction.objects[fact_filter_lvli]);
        if (result) then exit;
    end;
    
end;

//============================================================================
function evalItem(item: IInterface): boolean;
var
    sig: string;
    countmaster, countPaintjobs: integer;
    faction, paintjobs: TStringList;
    paintjob : IInterface;
    
begin
    //filter out non playable and unused
    result := false;
    if (getElementEditValues(item, 'Record Header\record flags\Non-Playable') = '1') then exit; //skip unplayable items
    if not assigned(ElementByPath(item, 'Object Template\Combinations')) then exit; //skip items completely missing templates
    if (winningRefByCount(item) < 1) then exit; //skip unused items
    if not isRecordFiltered(item, filter_eval_item) then exit;
    sig := signature(item);
    
    addMessage('***** Evaluating '+ getFileName(getFile(item)) + ' - ' + EditorID(item) + ' '+ IntToHex(GetLoadOrderFormID(item), 8) + ' *****');
    //true exit conditions
    result := true;
    
    //Check for a compatible paint job
    for countMaster := 0 to listMaster.count -1 do begin
        faction := listMaster.objects[countMaster];
        paintjobs := faction.objects[fact_paintjobs];
        for countPaintjobs := 0 to paintjobs.count-1 do begin
            paintJob := ObjectToElement(paintJobs.objects[countPaintjobs]);
            if isPaintjobCompatibleKeyword(paintjob, item) then exit;
            if isPaintjobCompatibleMatswap(paintjob, item) then exit;
        end;
    end;

    //if no match, the false
    result := false;    
end;

//============================================================================
function processLVLI(lvli: IInterface): boolean;
var
    i : integer;
    faction: TStringList;
begin
    addMessage('***** Processing '+ EditorID(lvli) + ' '+ IntToHex(GetLoadOrderFormID(lvli), 8) + ' *****');
    //If the editorID contains one of the faction search terms, then flag it for patching.
    for i := 0 to listFactions.count-1 do begin
        faction := listFactions.objects[i];
        //skip to next if
        if not isRecordFiltered(lvli, faction.objects[fact_filter_lvli]) then continue;
        addFilterKeywordToLVLI(lvli, faction[fact_kywd]);
        exit;
    end;

    //TODO Add Epic Keyword to "CustomItem_DoNotPlaceDirectly", "Aspiration"
end;
//============================================================================
procedure processItem(item: IInterface);
var
    faction, listAp_listCompatiblePaintjobs, listApprModcol: TStringList;
    countFaction, i : integer;

begin
    addMessage('***** Processing '+ EditorID(item) + ' '+ IntToHex(GetLoadOrderFormID(item), 8) + ' *****');

    //generate Default, and apply
    faction := getItemDefaultFaction(item);
    if assigned(faction) then begin 
        listAp_listCompatiblePaintjobs := getCompatiblePaintjobs(item, faction);
        listApprModcol := getFactionModcols(faction, listAp_listCompatiblePaintjobs);
        applyDefaultModcols(item, faction, listApprModcol);
        for i := 0 to listAp_listCompatiblePaintjobs.count-1 do listAp_listCompatiblePaintjobs.objects[i].free;
        listAp_listCompatiblePaintjobs.free;
        listApprModcol.free;
    end
    else logg(4, 'No default faction found for ' + editorId(item));
    
    //generate Epic, and apply
    faction := getItemEpicFaction(item);
    if assigned(faction) then begin 
        listAp_listCompatiblePaintjobs := getCompatiblePaintjobs(item, faction);
        listApprModcol := getFactionModcols(faction, listAp_listCompatiblePaintjobs);
        applyFactionModcols(item, faction, listApprModcol);
        for i := 0 to listAp_listCompatiblePaintjobs.count-1 do listAp_listCompatiblePaintjobs.objects[i].free;
        listAp_listCompatiblePaintjobs.free;
        listApprModcol.free;
    end
    else logg(4, 'No epic faction found for ' + editorId(item));

    //generate Standard Factions, and apply
    for countFaction := 0 to listFactions.count-1 do begin
        faction := listFactions.objects[countFaction];
        logg(1, 'Faction: ' + faction[fact_name]);
        if not isRecordFiltered(item, faction.objects[fact_filter_item]) then begin
            logg(1, 'Failed faction item filter, skipping');
            continue;
        end;
        listAp_listCompatiblePaintjobs := getCompatiblePaintjobs(item, faction);
        listApprModcol := getFactionModcols(faction, listAp_listCompatiblePaintjobs);
        applyFactionModcols(item, faction, listApprModcol);
        for i := 0 to listAp_listCompatiblePaintjobs.count-1 do listAp_listCompatiblePaintjobs.objects[i].free;
        listAp_listCompatiblePaintjobs.free;
        listApprModcol.free;
    end;

    if hasKwda(item, 'ArmorTypePower') then begin
        //generate Default PA Sets, and apply
        for countFaction := 0 to listDefaultPaSets.count-1 do begin
            faction := listDefaultPaSets.objects[countFaction];
            if not isRecordFiltered(item, faction.objects[fact_filter_item]) then continue;
            listAp_listCompatiblePaintjobs := getCompatiblePaintjobs(item, faction);
            listApprModcol := getFactionModcols(faction, listAp_listCompatiblePaintjobs);
            applyFactionModcols(item, faction, listApprModcol);
            for i := 0 to listAp_listCompatiblePaintjobs.count-1 do listAp_listCompatiblePaintjobs.objects[i].free;
            listAp_listCompatiblePaintjobs.free;
            listApprModcol.free;
        end;
        //generate Epic PA Sets, and apply
        for countFaction := 0 to listEpicPaSets.count-1 do begin
            faction := listEpicPaSets.objects[countFaction];
            if not isRecordFiltered(item, faction.objects[fact_filter_item]) then continue;
            listAp_listCompatiblePaintjobs := getCompatiblePaintjobs(item, faction);
            listApprModcol := getFactionModcols(faction, listAp_listCompatiblePaintjobs);
            applyFactionModcols(item, faction, listApprModcol);
            for i := 0 to listAp_listCompatiblePaintjobs.count-1 do listAp_listCompatiblePaintjobs.objects[i].free;
            listAp_listCompatiblePaintjobs.free;
            listApprModcol.free;
        end;
    end;
    
end;

//============================================================================
procedure applyDefaultModcols(item: IInterface; faction, listApprModcol: TStringList);
var
    countTemplate, countAp, parentIndex: integer;
    templates, template, modcol: IInterface;
begin
    if (listApprModcol.count = 0) then begin
        logg(5, 'applyDefaultModcols: listApprModcol.count = 0');
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
    countTemplate, countAlt, countAp, parentIndex: integer;
    templates, template: IInterface;
    kwdaFormId : cardinal;
    hasFactionTemplate : boolean;
begin
    if (listApprModcol.count = 0) then begin
        logg(5, 'applyFactionModcols: listApprModcol.count = 0');
        exit;
    end;

    //if already has faction, then enrich, ELSE create version for each default
    hasFactionTemplate := false;
    templates := ElementByPath(item, 'Object Template\Combinations');
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
		
    if hasFactionTemplate then exit;

    for countTemplate := 0 to ElementCount(templates)-1 do Begin
        template := ElementByIndex(templates, countTemplate);
        parentIndex := StrToInt(GetElementEditValues(template, 'OBTS\Parent Combination Index'));
        if (parentIndex <> -1) then exit; //If we've hit the non-basic templates, then we're done.
        generateFactionVersionOfTemplate(item, faction, listApprModcol, parentIndex);
    end;
            
end;

//============================================================================  
procedure generateFactionVersionOfTemplate(item: IInterface; faction, listApprModcol: TStringList; parentIndex: integer);
var
    entry, newKeyword, listmods, addmod, modID, modcol : IInterface;
    i: integer;
begin
    //Add faction copies of this template for each registered faction modcol
    logg(1, 'Generating faction version of template ' + intToStr(parentIndex));
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
//Returns a TStringList map of <AP, PaintjobList>
function getCompatiblePaintjobs(item: IInterface; faction: TStringList): TStringList;
var
    paintjobs, paintjobsForAP: TStringList;
    paintJob, ap, mnam: IInterface;
    apIndex, countPaintjobs, i : integer;
    isCompatible : boolean;
begin
    result := TStringList.create;
    paintjobs := faction.objects[fact_paintjobs];
            
    if (paintjobs.count = 0) then logg(1, 'No paintjobs found for ' + faction[fact_name]);
    for countPaintjobs := 0 to paintjobs.count-1 do begin
        paintJob := ObjectToElement(paintJobs.objects[countPaintjobs]);
        isCompatible := false;
        ap := linksTo(elementByPath(paintjob, 'DATA\Attach Point'));
        mnam := getPaintjobMnam(paintjob);
        
        //Build paintjob modcols: check for compatibility, by keywords then by matSwap
        if isPaintjobCompatibleKeyword(paintJob, item) then begin
            isCompatible := true
            //TODO - add this as a configurable option?
            //if not isPaintjobCompatibleMatswap(paintJob, item) then logg(5, 'Found paintjob with compatible keywords but no compatible MatSwaps for applicable item: ' + editorID(paintjob) + ', ' + editorId(item))
        end
        else if isPaintjobCompatibleMatswap(paintJob, item) then begin
            if isRecordFiltered(mnam, filter_paintjob_kywd) then begin
                logg(3, 'Adding missing keyword:AP :    ' + editorId(mnam) + ':' + editorId(ap));
                isCompatible := true;//check if it's a known generic paintjob keyword
                addMissingKywdAp(mnam, ap, item);
            end else logg(4, 'SKIPPING: Found compatible mat swap, but unrecognized material keyword: ' + editorId(mnam));
        end;
        
        //continue if not compatible
        if not isCompatible then continue;
        
        apIndex := result.indexOf(EditorId(ap));
        if (apIndex > -1) then paintjobsForAP := result.Objects[apIndex]
        else begin 
            paintjobsForAP := TStringList.create;
            result.addObject(editorId(ap), paintjobsForAP);
        end;
        paintjobsForAP.addObject(editorId(paintjob), paintjob);
        
    end;
    logg(1, faction[fact_name] + ': Num APs: ' + intToStr(result.count));
    for i := 0 to result.count-1 do logg(1, 'AP: ' + result[i] + ' numPaintjobs: ' + intToStr(result.objects[i].count));

end;

//============================================================================
//Converts a list<Ap, listAllFactionFilteredPaintjobs> to a list <AP, modcol>>
function getFactionModcols(faction, listAp_listCompatiblePaintjobs: TStringList): TStringList;
var
    ap, modcol, paintjob, entry: IInterface;
    mnamEdids, listCompatiblePaintjobs: TStringList;
    modcolEdid : String;
    paintjobCount, apCount: integer;

begin
    result := TStringList.create;
    
    for apCount := 0 to listAp_listCompatiblePaintjobs.count-1 do begin
        listCompatiblePaintjobs := listAp_listCompatiblePaintjobs.objects[apCount];
        ap := linksTo(elementByPath(ObjectToElement(listCompatiblePaintjobs.objects[0]), 'DATA\Attach Point'));
        logg(1, 'getFactionmodcols - ' + faction[fact_name] + ': '  + editorId(ap) + ', num paintjobs=' + intToStr(listCompatiblePaintjobs.count));
        mnamEdids := concatMnams(listCompatiblePaintjobs);
        modcolEdid := 'modcol_'+ '_' + mnamEdids + '_' + editorId(ap) + '_' + faction[fact_name];
        modcol := MainRecordByEditorID(GroupBySignature(mxPatchFile, 'OMOD'), modcolEdid);
        
        //If the modcol already exists, then I don't need to do anything else, it's already correctly populated with the same filter output
        if assigned(modcol) then begin
            logg(1, 'Modcol already exists: ' + modcolEdid);
            
        end else begin //create it new
        
            modcol := wbCopyElementToFile(template_modcol, mxPatchFile, true, true);
            SetElementEditValues(modcol, 'EDID', modcolEdid);
            SetElementEditValues(modcol, 'FULL', faction[fact_name]);
            SetEditValue(ElementByPath(modcol, 'DATA\Attach Point'), IntToHex(GetLoadOrderFormID(ap), 8));
            
            //add each paintjob to the modcol
            for paintjobCount := 0 to listCompatiblePaintjobs.count-1 do begin
                paintjob := ObjectToElement(listCompatiblePaintjobs.objects[paintjobCount]);
                if paintjobCount = 0 then entry := ElementByIndex(ElementByPath(modcol, 'DATA\Includes'), 0)
                else entry := ElementAssign(ElementByPath(modcol, 'DATA\Includes'), HighInteger, nil, False);
                setElementEditValues(entry, 'Mod', IntToHex(GetLoadOrderFormID(paintjob), 8));
            end;
            
        end;
        //add the ap specific modcol to the modcol map
        result.addObject(editorId(ap), modcol);
    end;

end;

//============================================================================
function concatMnams(paintjobs:tstringlist): String;
var
    mnams : TStringList;
    paintjob: IInterface;
    mnam: string;
    i, j: integer;
begin
    mnams := TStringList.create;
    mnams.Delimiter := '-';
    for i := 0 to paintjobs.count-1 do begin
        paintjob := ObjectToElement(paintjobs.objects[i]);
        for j := 0 to elementCount(ElementByPath(paintjob, 'MNAM'))-1 do begin
            mnam := editorId(LinksTo(ElementByIndex(ElementByPath(paintjob, 'MNAM'), j)));
            if mnams.indexOf(mnam) > -1 then continue;
            mnams.add(mnam);
        end;
    end;
    result := mnams.DelimitedText;
    mnams.Free;
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

    if not isRecordFiltered(furn, filter_eval_furn) then exit;

    addMessage('***** Evaluating '+ getFileName(getFile(furn)) + ' - ' + EditorID(furn) + ' '+ IntToHex(GetLoadOrderFormID(furn), 8) + ' *****');
    
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
        if isRecordFiltered(furn, listFactions.objects[countFact].objects[fact_filter_lvli]) OR isRecordFiltered(lvli, listFactions.objects[countFact].objects[fact_filter_lvli]) then begin
            faction := listFactions.objects[countFact];
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
function getItemDefaultFaction(item: IInterface): TStringList;
var
    i: integer;
    faction: TStringList;
begin
    for i := 0 to listDefaultFactions.count-1 do begin
        faction := listDefaultFactions.objects[i];
        if isRecordFiltered(item, faction.objects[fact_filter_item]) then begin
            //logg(1, 'Found default faction ' + faction[fact_name] + ' for item' + editorId(item));
            result := faction;
            exit;
        end;
    end;
    logg(4, 'No default faction found for ' + editorId(item));
end;

//============================================================================  
function getItemEpicFaction(item: IInterface): TStringList;
var
    i: integer;
    faction: TStringList;
begin
    for i := 0 to listEpicFactions.count-1 do begin
        faction := listEpicFactions.objects[i];
        if isRecordFiltered(item, faction.objects[fact_filter_item]) then begin
            //logg(1, 'Found epic faction ' + faction[fact_name] + ' for item' + editorId(item));
            result := faction;
            exit;
        end;
    end;
    logg(4, 'No epic faction found for ' + editorId(item));
end;

//============================================================================  
function isRecordFiltered(rec: String; filterList: TStringList): boolean;
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
        else if filter[1] = 'keyword' then hasText := hasKwda(rec, filter[2]) 
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
  modcolAp: cardinal;
  omod, addmod, flag, includes: IInterface;


begin
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
    logg(1, 'Added as new ' + editorId(modcol));
  
end;

//============================================================================
function getPaintjobMnam(paintjob: IInterface): IInterface;
var
  temp : IInterface;
  i : Integer;
begin
    for i := 0 to elementCount(ElementBySignature(paintjob, 'MNAM'))-1 do begin
        temp := winningOverride(linksTo(ElementByIndex(ElementBySignature(paintjob, 'MNAM'), i)));
        if isRecordFiltered(temp, filter_paintjob_kywd) then begin
            result := temp;
            exit;
        end;
    end;
    //if not assigned(result) then logg(4, 'Unable to identify a paintjob relevant mnam for ' + editorId(paintjob));
    result := winningOverride(LinksTo(ElementByIndex(ElementBySignature(paintjob, 'MNAM'), 0)));
end;
//============================================================================
function getShouldGenerateFactionTemplates(item: IInterface): integer;
var
  i, countFaction: integer;
  keywords: IwbElement;
begin
    //TODO - reconfigure this to load from a config file?
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
function modcolContainsOmod(modcol, omod: IInterface): boolean;
var
  listMods : IInterface;
  i : Integer;
begin
    listmods := ElementByPath(modcol, 'DATA\Includes');
    
    for i := 0 to ElementCount(listMods)-1 do begin
      //Todo- verify this works, and doesn't need to be replaced with a formID comparison
      if winningOverride(LinksTo(ElementByPath(ElementByIndex(listMods, i), 'Mod'))) <> omod then continue;
        result := true;
        exit;
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
