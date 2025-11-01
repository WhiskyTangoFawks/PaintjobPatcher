unit FPD_main;

uses 'lib\mxpf';
uses 'FactionPaintjobs\libs\factions';
uses 'FactionPaintjobs\libs\paintjobs';
uses 'FactionPaintjobs\libs\omod_cobj';
uses 'FactionPaintjobs\libs\lvli';
uses 'FactionPaintjobs\libs\furn';
uses 'FactionPaintjobs\libs\weap_armo';
uses 'FactionPaintjobs\libs\compat';

var
    listMaterials, listPaintjobFingerprints: TStringList;
    template_keyword, template_modcol, template_pa_lvli : IInterface;
    epic_kywd_formId : cardinal;
    pa_kwd_hex: string;

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
    pa_kwd_hex := intToHex(GetLoadOrderFormID(MainRecordByEditorID(GroupBySignature(fileByName('Fallout4.esm'), 'KYWD'), 'ArmorTypePower')), 8);

    //SetExclusions('Fallout4.esm,DLCCoast.esm,DLCRobot.esm,DLCNukaWorld.esm,DLCWorkshop01.esm,DLCWorkshop02.esm,DLCWorkshop03.esm');
    
    // select/create a new patch file that will be identified by its author field
    PatchFileByAuthor('FactionPaintjobPatcher');
    
    slMasters := TStringList.Create;
    slMasters.Add('FactionPaintjobs.esp');
    AddMastersToFile(mxPatchFile, slMasters, False);
    
    //Initialize the faction config file;
    initConfig();
    initFactions();
    initCompat();

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

    //*Process OMODs and COBJs first, so Paintjobs are Indexed
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Processing OMODS/COBJs');
    for i := 0 to MaxPatchRecordIndex do if (signature(GetPatchRecord(i)) = 'COBJ') then processOmodAndCobj(GetPatchRecord(i));
    
    //After indexing the paintjobs, any factions that don't have any paintjobs mapped for them can be disabled.
    removeFactionsWithNoPaintjobs();

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

//============================================================================
function Finalize: integer;
var
    i: integer;
begin
	addMessage('   ');
    addMessage('   ');
    addMessage('** Finalizing Patch **');
    
    for i := 0 to MaxPatchRecordIndex do begin 
        if (signature(GetPatchRecord(i)) <> 'COBJ')  AND (ReferencedByCount(GetPatchRecord(i)) < 1) then logg(5, 'Found unreferenced patch record: ' + EditorID(GetPatchRecord(i)) + ' '+ IntToHex(GetLoadOrderFormID(GetPatchRecord(i)), 8) + ' *****');
        removeIdenticalToMaster(GetPatchRecord(i));
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
function winningRefByCount(e: IInterface): integer;
var
    i: integer;

begin
    result := 0;
    for i := 0 to ReferencedByCount(e)-1 do 
        if isWinningOverride(ReferencedByIndex(e, i)) then result := result + 1;
      
end;
//============================================================================
function modcolContainsOmod(modcol, omod: IInterface): boolean;
var
  listMods : IInterface;
  i : Integer;
begin
    listmods := ElementByPath(modcol, 'DATA\Includes');
    
    for i := 0 to ElementCount(listMods)-1 do begin
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
//=======================
function getOrAddList(list: TStringList; key: String): TStringList;
var
    i: integer;
begin
    i := list.indexOf(key);
    if (i = -1) then begin
        result := TStringList.create;
        list.addObject(key, result);
    end
    else result := list.objects[i];
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
