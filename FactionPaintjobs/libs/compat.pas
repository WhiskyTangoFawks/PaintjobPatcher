unit FDP_compat;
var
    listCompatMatswaps, listCompatKeywords, apprsToAdd, kywdsToAdd: TStringList;
//============================================================================
procedure initCompat();
begin
    listCompatMatswaps := TStringList.create;
    listCompatMatswaps.sorted := true;
    listCompatMatswaps.Duplicates := dupIgnore;

    listCompatKeywords := TStringList.create;
    listCompatKeywords.sorted := true;
    listCompatKeywords.Duplicates := dupIgnore;

    kywdsToAdd := TStringList.create;
    kywdsToAdd.sorted := true;
    kywdsToAdd.Duplicates := dupIgnore;

    apprsToAdd := TStringList.create;
    apprsToAdd.sorted := true;
    apprsToAdd.Duplicates := dupIgnore;
end;

//============================================================================
procedure registerPaintjobMaterials(omod: IInterface);
var
    appr, mnam: IInterface;
    i, apprKywdIndex, matIndex: integer;
    apId, mnamId, apprKywd: string;
    replacedMaterials, listApprKywd, oldMatList: TStringList;

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

    //For each matswap, register 
    for i := 0 to replacedMaterials.count-1 do begin
        matIndex := listCompatMatswaps.indexOf(replacedMaterials[i]);
        //TODO - I'm not entirely sure how this will handle subsets- it should be detected in the previous step and exitted early
        if matIndex = -1 then listCompatMatswaps.addObject(replacedMaterials[i], listApprKywd)
        else listCompatMatswaps.objects[matIndex] := listApprKywd;
    end;

end;
//============================================================================
function evalMissingKeywords(item: IInterface; cacheApprFormId, cacheKywdFormId: TStringList): boolean;
var
    cacheMatSwap, apprKywd : TStringList;
    i, matIndex : Integer;
    apprId, kywdId: String;
begin
    result := false;
    cacheMatSwap := getMaterials(item);
    
    //for each material with an indexed material swap
    for i := 0 to cacheMatSwap.count-1 do begin
        matIndex := listCompatMatswaps.indexOf(cacheMatSwap[i]);
        if (matIndex = -1) then continue;
        apprKywd := listCompatMatswaps.objects[matIndex];
        apprId := apprKywd[0];
        kywdId := apprKywd[1];
        
        if cacheApprFormId.indexOf(apprId) = -1 then begin 
            getOrAddList(apprsToAdd, IntToHex(getLoadOrderFormId(item), 8)).add(apprId);
            cacheApprFormId.add(apprId);
            result := true;
        end;
        if cacheKywdFormId.indexOf(kywdId) = -1 then begin 
            getOrAddList(kywdsToAdd, IntToHex(getLoadOrderFormId(item), 8)).add(kywdId);
            cacheKywdFormId.add(kywdId);
            result := true;
        end;
    end;
    cacheMatSwap.free;
end;
//============================================================================

procedure processMissingKeywords(item: IInterface);
var
    formId: String;
    apprIndex, kywdIndex, i: integer;
    entry: IInterface;
    list: TStringList;

begin
    formId := IntToHex(getLoadOrderFormId(item),8);
    apprIndex := apprsToAdd.indexOf(formId);
    if apprIndex <> -1 then begin
        list := apprsToAdd.objects[apprIndex];
        for i := 0 to list.count-1 do begin
            entry := ElementAssign(ElementByPath(item, 'APPR'), HighInteger, nil, False);
            logg(3, 'Adding Attach Point ' + list[i]);
            setEditValue(entry, list[i]);
        end;
    end;
    kywdIndex := kywdsToAdd.indexOf(formId);
    if kywdIndex <> -1 then begin
        list := kywdsToAdd.objects[kywdIndex];
        for i := 0 to list.count-1 do begin
            entry := ElementAssign(ElementByPath(item, 'Keywords\KWDA'), HighInteger, nil, False);
            logg(3, 'Adding keyword ' + list[i]);
            setEditValue(entry,  list[i]);
        end;
    end;

end;


end.