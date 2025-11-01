unit FPD_Paintjobs;


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
function isPaintjobCompatibleKeyword(paintjob: IInterface; cacheApprFormId, cacheKywdFormId: TStringList): boolean;
var
    mnamId, apId: string;
    i : integer;
    entries : IInterface;
begin
    result := false;
    
    //check if the thing has the correct keyword and ap
    if not cacheContains(cacheApprFormId, linksTo(elementByPath(paintjob, 'DATA\Attach Point'))) then exit;

    for i := 0 to elementCount(ElementByPath(paintjob, 'MNAM'))-1 do 
        if not cacheContains(cacheKywdFormId, LinksTo(ElementByIndex(ElementByPath(paintjob, 'MNAM'), i)))
            then exit;

    result := true;
end;
//============================================================================
function getPaintjobMnam(paintjob: IInterface): IInterface;
var
  temp : IInterface;
  i : Integer;
begin
    for i := 0 to elementCount(ElementBySignature(paintjob, 'MNAM'))-1 do begin
        temp := winningOverride(linksTo(ElementByIndex(ElementBySignature(paintjob, 'MNAM'), i)));
        if isKeywordFiltered(temp, filter_paintjob_kywd) then begin
            result := temp;
            exit;
        end;
    end;
    //if not assigned(result) then logg(4, 'Unable to identify a paintjob relevant mnam for ' + editorId(paintjob));
    result := winningOverride(LinksTo(ElementByIndex(ElementBySignature(paintjob, 'MNAM'), 0)));
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
    result.Sorted := true;
    result.Duplicates := dupIgnore;
    
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


end.