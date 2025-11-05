unit wtfxpf;
var
    recordQueue: TList;
    excludedFiles: TStringList;
    patchFile: file;

//=======
procedure PatchFileByAuthor(author: string);
var
    fileHeader: IInterface;
    i : integer;
begin
    for i := 0 to FileCount-1 do begin
        if (getElementEditValues(ElementByIndex(FileByIndex(i), 0), 'CNAM - Author') <> author) then continue;
        patchFile := FileByIndex(i);
        break;
    end;
    if not assigned(patchFile) then begin
        patchFile := AddNewFile;
        fileHeader := ElementByIndex(patchFile, 0);
        SetElementEditValues(fileHeader, 'CNAM - Author', author);
  end;
  

  addExclusion(getFileName(patchFile));
end;

//===========
procedure addExclusion(fileName: string);
begin
    if not assigned(excludedFiles) then begin
        excludedFiles := TStringList.create;
        excludedFiles.Duplicates := dupIgnore;
        excludedFiles.sorted := true;
    end;
    excludedFiles.add(fileName);
end;

//=========================================================================
// RECORD PROCESSING
//=========================================================================
procedure loadRecordQueue(sig: string);
var
  i, j: Integer;
  f, g, rec: IInterface;
begin
    if not assigned(recordQueue) then recordQueue := TList.create;

    for i := Pred(FileCount) downTo 0 do begin
        f := FileByIndex(i);
        if (excludedFiles.IndexOf(GetFileName(f)) <> -1) then continue;
        
        // get group from file
        g := GroupBySignature(f, sig);
        if not Assigned(g) then continue;
        
        // loop through records in group
        for j := 0 to Pred(ElementCount(g)) do begin
            rec := ElementByIndex(g, j);
            if not isWinningOverride(rec) then continue;
        
            // add record to list
            recordQueue.Add(TObject(rec));
        end;

    end;
end;

//=======
function recordQueueHasNext(): boolean;
begin
    result := recordQueue.count > 0;
end;

//=======
function getQueueNextRecord(): IInterface;
var
    count: integer;
begin
    
    count := recordQueue.count-1;
    result := ObjectToElement(recordQueue[count]);
    recordQueue.delete(count);
end;

//============
function copyOverrideToPatch(rec: IInterface):IInterface;
begin
    if getFileName(getFile(rec)) = getFileName(patchFile) then begin
        result := rec;
        exit;
    end;
    result := copyRecordToFile(rec, patchFile, false);
end;

//============
function copyRecordToFile(rec, f: IInterface; asNew: boolean):IInterface;
var
    i, patchMastersCount: integer;
    masters: IInterface;
    fileName : string;
begin
    if not assigned(f) then raise exception.create('Tried to call copyRecordToFile without a patchfile set');
    
    masters := ElementByPath(ElementByIndex(GetFile(rec), 0), 'Master Files');
    patchMastersCount := elementCount(ElementByPath(ElementByIndex(f, 0), 'Master Files'));
    if patchMastersCount + elementCount(masters) > 254 then begin
        cleanMasters(f);
        patchMastersCount := elementCount(ElementByPath(ElementByIndex(f, 0), 'Master Files'));
        if patchMastersCount + elementCount(masters) > 254 then begin
            raise exception.create('Unable to add all potentially required masters to patch');
        end;
    end;

    AddMasterIfMissing(f, GetFileName(GetFile(rec)));
    for i := 0 to ElementCount(masters) - 1 do begin
        AddMasterIfMissing(f, getElementEditValues(ElementByIndex(masters, i), 'MAST'));
    end;
    result := wbCopyElementToFile(rec, f, asNew, True);
end;
//============
function removeIdenticalToMaster(e: IInterface): integer;
var
  m, prevovr, ovr: IInterface;
  i: integer;
begin
  //logg(1, 'Checking for identical to master: ' + Name(e));
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
     //logg(1, 'Removing: ' + Name(e));
    remove(e);
  end;
end;

//============
procedure cleanPatchGroup(sig: string);
var
    g: IInterface;
    i: integer;
begin
    g := GroupBySignature(patchFile, sig);
    if not Assigned(g) then continue;
    for i := 0 to Pred(ElementCount(g)) do removeIdenticalToMaster(ElementByIndex(g, i));
end;

//============
end.