unit FPD_main;

uses 'FactionPaintjobs\libs\wtf_xpf';
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
    log_level = 3; //1=trace, 2=debug, 3=info, 4=warn, 5=error

function Initialize: Integer;
var
  i: integer;
    slMasters: TStringList;
  
begin
    if not assigned(masterPlugin) then raise Exception.Create('**ERROR** Failed to find FactionPaintjobs.esp');
        
    template_keyword := MainRecordByEditorID(GroupBySignature(masterPlugin, 'KYWD'), 'if_tmp_Template_Restricted');
    if not assigned(template_keyword) then raise Exception.create('** ERROR ** Failed to find template_keyword');
    
    template_modcol := MainRecordByEditorID(GroupBySignature(masterPlugin, 'OMOD'), 'modcol_template');
    if not assigned(template_modcol) then raise Exception.create('** ERROR ** Failed to find template_modcol');
    
    template_pa_lvli := MainRecordByEditorID(GroupBySignature(masterPlugin, 'LVLI'), 'LL_Armor_Power_Set_Template');
    if not assigned(template_pa_lvli) then raise Exception.create('** ERROR ** template_pa_lvli');
    
    epic_kywd_formId := GetLoadOrderFormID(MainRecordByEditorID(GroupBySignature(fileByName('Fallout4.esm'), 'KYWD'), 'if_Epic_Restricted'));
    pa_kwd_hex := intToHex(GetLoadOrderFormID(MainRecordByEditorID(GroupBySignature(fileByName('Fallout4.esm'), 'KYWD'), 'ArmorTypePower')), 8);

    addExclusion('Unique NPCs - Creatures and Monsters.esp');
    PatchFileByAuthor('FactionPaintjobPatcher');

    
    //Initialize the faction config file;
    initConfig();
    initFactions();
    initCompat();

    //Load the paintjobs, and copy Paintjobs to patch, so we can then filter COBJs by checking if the CNAM is in the patch
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('** Evaluating OMODs as potential paintjobs **');
    loadRecordQueue('OMOD');
    while recordQueueHasNext do evalOmod(getQueueNextRecord());
    

    //Load COBJs, and remove if the CNAM isn't in the patch
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('** Processing COBJs/OMODs **');
    loadRecordQueue('COBJ');
    while recordQueueHasNext do processOmodAndCobj(getQueueNextRecord());

    //After indexing the paintjobs, any factions that don't have any paintjobs mapped for them can be disabled.
    removeFactionsWithNoPaintjobs();
    
    //Load LVLIs to the patch and copy, so we can then filter FURNs if the LVLI is already in the patch;
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Processing Lvlis');
    loadRecordQueue('LVLI');
    while recordQueueHasNext do processLVLI(getQueueNextRecord());
    
    //Process Remaining Records
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Evaluating ARMOs for patching');
    loadRecordQueue('ARMO');
    while recordQueueHasNext do processItem(getQueueNextRecord());
    
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Evaluating WEAPs for patching');
    loadRecordQueue('WEAP');
    while recordQueueHasNext do processItem(getQueueNextRecord());
    
    AddMessage('   ');
    AddMessage('   ');
    AddMessage('Evaluating FURNs for patching');
    loadRecordQueue('FURN');
    while recordQueueHasNext do processFurn(getQueueNextRecord());

    //TODO - Eval Outfits, and make faction copies of lists they use that aren't faction specific

end;

//============================================================================
function Finalize: integer;
var
    i: integer;
begin
	addMessage('   ');
    addMessage('   ');
    addMessage('** Finalizing Patch **');
    
    cleanPatchGroup('FURN');
    cleanPatchGroup('ARMO');
    cleanPatchGroup('WEAP');
    cleanPatchGroup('COBJ');
    cleanPatchGroup('OMOD');
    CleanMasters(patchFile);
    sortMasters(patchFile);
    
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
    ref: IInterface;
begin
    result := 0;
    for i := 0 to ReferencedByCount(e)-1 do begin
        ref := ReferencedByIndex(e, i);
        if Copy(editorId(ref), 1, 2) = 'QA' then continue;
        if isWinningOverride(ref) then result := result + 1;
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

//===
end.
