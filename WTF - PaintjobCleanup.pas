unit PaintjobCleanup;
var
    template: IInterface;
    matList :TStringList;

//============================================================================
function Initialize: Integer;
  
begin
    template := MainRecordByEditorID(GroupBySignature(fileByName('Fallout4.esm'), 'KYWD'), 'ma_armor_lining');
    matList := TStringList.create;
    matList.sorted := true;
    matList.Duplicates := dupIgnore;
end;

//============================================================================
function Process(e: IInterface): integer;
var
    isFirstRef : boolean;
    i, j: integer;
    omod, cobj: IInterface;
    sig : string;
begin
    sig := signature(e);
    if sig = 'MSWP' then cleanupDuplicateOmods(e)
    else if (sig = 'ARMO') or (sig='WEAP') then remove(e);


end;

//============================================================================
procedure cleanupDuplicateOmods(matswap: IInterface);
var
    i: integer;
    omod, winner:IInterface;
    mnam: string;
begin
       
    for i := ReferencedByCount(matswap)-1 downto 0 do begin
        omod := ReferencedByIndex(matswap, i);
        if signature (omod) <> 'OMOD' then continue;
        
        if not assigned(winner) then winner := omod
        //always remove the "lesser" string, this is to try and remove things uniformly, and not end up with a mixed bag of removed stuff in complex mods
        else if editorId(winner) < editorId(omod) then begin
            removeOmod(omod);
            continue;
        end
        else begin
            removeOmod(winner);
            winner := omod;
        end;
    end;

    mnam := editorId(LinksTo(ElementByIndex(ElementByPath(omod, 'MNAM'), 0)));
    //addMessage('founhd mnam ' + mnam);
    if (elementCount(elementByPath(omod, 'MNAM')) = 1) 
        AND (NOT containsText(mnam, 'harvest'))
        then setUniqueKeyword(matswap, omod);
    
end;


//============================================================================
procedure setUniqueKeyword(matswap, omod: IINterface);
var
    keyword: IInterface;
    matString: String;
    i: integer;
begin

    matString := getReplacedMaterialsForMatSwap(matswap);
    i := matList.indexOf(matString);
    if (i > -1) then keyword := objectToElement(matList.objects[i])
    else begin
        keyword := wbCopyElementToFile(template, getFile(matswap), true, true);
        setElementEditValues(keyword, 'EDID', 'ma_color_' + editorId(matSwap));
        matList.addObject(matString, keyword);
    end;

    omod := ReferencedByIndex(matswap, 0);
    SetEditValue(ElementByIndex(ElementByPath(omod, 'MNAM'), 0), intToHex(getLoadOrderFormId(keyword), 8));

    cleanupDuplicateCobjs(omod)
end;


//============================================================================
procedure cleanupDuplicateCobjs(omod: IInterface);
var
    i, count: integer;
    cobj: IInterface;
begin
    if (getElementEditValues(omod, 'Record Header\Record Flags\Mod Collection') = '1') then begin
        addMessage('Removing mod collection: ' + editorId(omod));
        remove(omod);
        exit;
    end;

    count := 0;
    for i := 0 to ReferencedByCount(omod)-1 do begin
        cobj := ReferencedByIndex(omod, i);
        if signature(cobj) <> 'COBJ' then continue
        count := count +1;
        if (count > 1) then begin
            addMessage('Found multple COBJs creating the same ' +editorId(omod)+ ', removing: ' + editorId(cobj));
            remove(cobj);
        end;
    end;
end;
//============================================================================
procedure removeOmod(omod: IInterface);
var
    j: integer;
    cobj: iinterface;
begin
    for j := ReferencedByCount(omod)-1 downto 0 do begin
        cobj := ReferencedByIndex(omod, j);
        if signature(cobj) <> 'COBJ' then begin 
            addMessage('Warning: Found non-cobj ref to the OMOD: ' + editorId(cobj));
            continue;
        end;
        addMessage('Removing COBJ: ' + editorId(cobj));
        remove(cobj);
    end;
    addMessage('Removing OMOD: ' + editorId(omod));
    remove(omod);
end;

//============================================================================
function getReplacedMaterialsForMatSwap(matswap: IInterface): string;
var
    substitutions: IInterface;
    j: integer;
    list: TStringList;
begin
    list := TStringList.create;
    list.Sorted := true;
    list.Duplicates := dupIgnore;

    substitutions := ElementByPath(matswap, 'Material Substitutions');
    //logg(1, EditorId(matSwap) + ' matswap ' + intToStr(ElementCount(substitutions)) + ' substitutions');
    for j := 0 to ElementCount(substitutions)-1 do begin
        list.add(normalizeMat(getElementEditValues(elementByIndex(substitutions, j), 'BNAM')));
    end;
    result := list.DelimitedText;
end;

//============================================================================
function normalizeMat(s: String): String;

begin
    result := lowerCase(s);
    result := StringReplace(result, ' ', '', [rfReplaceAll, rfIgnoreCase]);
    result := StringReplace(result, 'materials\', '', [rfReplaceAll, rfIgnoreCase]);
    result := StringReplace(result, '.BGSM', '', [rfReplaceAll, rfIgnoreCase]);
        
end;
end.
