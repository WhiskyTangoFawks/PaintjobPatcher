unit FPD_omod_cobj;

uses 'FactionPaintjobs\libs\paintjobs';

//============================================================================
function evalOmod(omod: IInterface): boolean;
var
    properties, refBy: IInterface;
    i, j: integer;
    listFaction, faction: TStringList;
    prop: string;
    hasMatSwap: boolean;
    appr: IInterface;
    
begin
    result := false;
    //exit if it's not a paintjob
    if getElementEditValues(omod, 'Record Header\Record Flags\Mod Collection') = '1' then exit;
    appr:= linksTo(elementByPath(omod, 'DATA\Attach Point'));
    if not assigned(appr) then exit;
    if not isKeywordFiltered(appr, filter_paintjob_ap) then exit;
    if not isOmodFiltered(omod, filter_eval_omod) then exit;

    addMessage('***** Evaluating Paintjob ' + getFileName(getFile(masterOrSelf(omod))) + ' - ' + EditorID(omod) + ' '+ IntToHex(GetLoadOrderFormID(omod), 8) + ' *****');
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

        if not isOmodFiltered(omod, filter_allow_redistribute) then begin
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
    omod, appr: IInterface;
    i: integer;
    faction, listAppr_listMnams, listMnams: TStringList;

begin
    omod := winningOverride(linksTo(elementByPath(cobj, 'CNAM')));
    addMessage('***** Processing Paintjob ' + getFileName(getFile(MasterOrSelf(omod))) + ' - ' + EditorID(omod) + ' '+ IntToHex(GetLoadOrderFormID(omod), 8) + ' *****');
    
    appr := linksTo(elementByPath(omod, 'DATA\Attach Point'));

    //Add the paintjob to the stored paintjob lists for the various factions
    for i := 0 to listMaster.count -1 do begin
        faction := listMaster.objects[i];
        logg(1, 'evaluating faction ' + faction[fact_name]);
        if isOmodFiltered(omod, faction.objects[fact_filter_paint]) then begin
            listAppr_listMnams := getOrAddList(faction.objects[fact_paintjobs], editorId(appr));
            listMnams := getOrAddList(listAppr_listMnams, concatMnams(omod));
            listMnams.addObject(IntToHex(GetLoadOrderFormID(omod), 8), omod);
            logg(3, 'FOUND MATCHING - Faction= ' + faction[fact_name] + ' paintjob= ' + editorId(omod));
        end 
        else logg(1, 'nonmatching: Faction= ' + faction[fact_name] + ' paintjob= ' + editorId(omod));
    
    end;

    //TODO - remove LNAM from OMOD configuration

    //TODO - process cobj
        //Crafting Recipe Standardization, Special Component?
        //Recipe Locking: Faction? Magazine?
    
    registerPaintjobMaterials(omod);
   
end;

end.