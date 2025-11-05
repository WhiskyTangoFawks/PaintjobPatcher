unit FDP_compat;
var
    listCompatMatswaps, listCompatKeywords: TStringList;
//============================================================================
procedure initCompat();
begin
    listCompatMatswaps := TStringList.create;
    listCompatMatswaps.sorted := true;
    listCompatMatswaps.Duplicates := dupIgnore;

    listCompatKeywords := TStringList.create;
    listCompatKeywords.sorted := true;
    listCompatKeywords.Duplicates := dupIgnore;
end;

//============================================================================
procedure registerPaintjobMaterials(omod: IInterface);
var
    appr, mnam: IInterface;
    i, apprKywdIndex, matIndex: integer;
    apId, mnamId, apprKywd: string;
    replacedMaterials, listApprKywd, listApprKywds, oldMatList: TStringList;

begin   
    //only index materials if it's a simple, single keyword paintjob. More complex paintjobs are distributed, but don't try to add their keywords to items
    if elementCount(elementByPath(omod, 'MNAM')) > 1 then exit;
    mnam := getPaintjobMnam(omod);
    appr := linksTo(elementByPath(omod, 'DATA\Attach Point'));
    if not isKeywordFiltered(mnam, filter_paintjob_kywd) then exit;
    
    apId := intToHex(getLoadOrderFormId(appr), 8);
    mnamId := intToHex(getLoadOrderFormId(mnam), 8);
    apprKywd :=  apId + ',' + mnamId;
    replacedMaterials := getReplacedMaterialsForPaintJob(omod);
    
    //register the appr+kywd
    apprKywdIndex := listCompatKeywords.indexOf(apprKywd);
    if (apprKywdIndex = -1) then listCompatKeywords.addObject(apprKywd, replacedMaterials)
    //IF already registered, only replace if the new list is bigger
    else begin
        oldMatList := listCompatKeywords.objects[apprKywdIndex];
        if (replacedMaterials.count > oldMatList.count) 
            then listCompatKeywords.objects[apprKywdIndex] := replacedMaterials
        //if we don't need to update anything, we can just exit
        else begin
            replacedMaterials.free;
            exit;
        end;
    end;
    
    listApprKywd := TStringList.create;
    listApprKywd.add(apId);
    listApprKywd.add(mnamId);

    //listCompatMatswaps is a list<matSwap, ApprKeyword>, and I need it to be a list of ApprKeyword

    //For each matswap, register 
    for i := 0 to replacedMaterials.count-1 do begin
        matIndex := listCompatMatswaps.indexOf(replacedMaterials[i]);
        if matIndex = -1 then begin
            listApprKywds := TStringList.create;
            listApprKywds.addObject(apprKywd, listApprKywd);
            listCompatMatswaps.addObject(replacedMaterials[i], listApprKywds)
        end
        else listCompatMatswaps.objects[matIndex].addObject(apprKywd, listApprKywd);
    end;

end;
//============================================================================
function addMissingKeywords(item: IInterface; cacheApprFormId, cacheKywdFormId: TStringList): IInterface;
var
    cacheMatSwap, apprKywds, apprKywd : TStringList;
    i, j, matIndex : Integer;
    apprId, kywdId: String;
    entry: iinterface;
begin
    cacheMatSwap := getMaterials(item);
    
    //for each material with an indexed material swap
    for i := 0 to cacheMatSwap.count-1 do begin
        matIndex := listCompatMatswaps.indexOf(cacheMatSwap[i]);
        if (matIndex = -1) then continue;
        apprKywds := listCompatMatswaps.objects[matIndex];
        for j := 0 to apprKywds.count-1 do begin
            apprKywd := apprKywds.objects[j];
            apprId := apprKywd[0];
            kywdId := apprKywd[1];
            
            if cacheApprFormId.indexOf(apprId) = -1 then begin 
                item := copyOverrideToPatch(item);
                if assigned(ElementByPath(item, 'APPR')) then entry := ElementAssign(ElementByPath(item, 'APPR'), HighInteger, nil, False)
                else entry := elementByIndex(add(item, 'APPR', true), 0);
                logg(3, 'Adding Attach Point ' + apprId);
                setEditValue(entry, apprId);
                cacheApprFormId.add(apprId);
            end;
            if cacheKywdFormId.indexOf(kywdId) = -1 then begin 
                item := copyOverrideToPatch(item);
                if assigned(ElementByPath(item, 'Keywords\KWDA')) then entry := ElementAssign(ElementByPath(item, 'Keywords\KWDA'), HighInteger, nil, False)
                else entry := elementByIndex(add(add(item, 'Keywords', true), 'KWDA', true), 0);
                logg(3, 'Adding keyword ' + kywdId);
                setEditValue(entry,  kywdId);
                cacheKywdFormId.add(kywdId);
            end;
        end;
    end;
    cacheMatSwap.free;
    result := item;
end;
//============================================================================


end.