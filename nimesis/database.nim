import
    strutils,
    os,
    asyncdispatch,
    asyncfile,
    tables,
    dataLogger,
    db_sqlite

# Database file name
const DATABASE_FILE_NAME = "database.dat"
# Script of database create
const CREATE_DATABASE_NAME = "createDatabase.sql"

# Field of class
const CLASS_PARENT* = 0
# Field of instance
const INSTANCE_PARENT* = 1

#############################################################################################
# Database types

type 
    DbEntity* = ref object of RootObj
        id* : BiggestUInt

    DbClass* = ref object of DbEntity        
        parentId* : BiggestUInt
        name* : string

    DbInstance* = ref object of DbEntity        
        classId* : BiggestUInt
        name* : string

    DbField* = ref object of DbEntity
        classId* : BiggestUInt
        name* : string
        isClassField* : uint8
        valueType* : uint8
        valueId* : BiggestUInt

    DbValue* = ref object of DbEntity
        fieldId* : BiggestUInt
        instanceId* : BiggestUInt

    DbIntValue* = ref object of DbValue
        value* : int
    
    DbFloatValue* = ref object of DbValue
        value* : float64

    DbStringValue* = ref object of DbValue
        value* : string

    DbEntityValue* = ref object of DbValue
        value* : uint64


#############################################################################################
# Workspace of database
type Workspace = ref object
    db : DbConn                     # Database connection

var workspace {.threadvar.} : Workspace

proc newWorkspace() : Workspace =
    # Create new workspace
    result = Workspace()

#############################################################################################
# Private

proc initDatabase() : void =
    # Init database
    if not os.fileExists(DATABASE_FILE_NAME):
        let createScript = "../assets/$1" % CREATE_DATABASE_NAME
        if not os.fileExists(createScript): 
            raise newException(Exception, "Can't find create database script")

        let file = asyncfile.openAsync(createScript, fmRead)
        let data = waitFor file.readAll()
        let db = open(DATABASE_FILE_NAME, "", "", "")
        db.exec(sql(data))
        workspace.db = db
    else:
        workspace.db = open(DATABASE_FILE_NAME, "", "", "")


#############################################################################################
# Public interface

proc writeLogRecord*(record : LogRecord) : void =
    # Write log record to database
    if record of AddClassRecord:
        let rec = AddClassRecord(record)
        workspace.db.exec(sql("INSERT INTO classes(id,parentId,name) VALUES(?,?,?)"), rec.id, rec.parentId, rec.name)
    if record of AddFieldRecord:
        let rec = AddFieldRecord(record)
        var parentType = CLASS_PARENT
        if not rec.isClassField:
            parentType = INSTANCE_PARENT
        workspace.db.exec(sql("INSERT INTO fields(id,name,parentType,parentId,valueType) VALUES(?,?,?,?,?)"), 
                          rec.id, rec.name, parentType, rec.classId, rec.valueType)

proc getAllClasses*() : TableRef[BiggestUInt, DbClass] = 
    # Iterate all classes from database
    result = newTable[BiggestUInt, DbClass]()
    for row in workspace.db.fastRows(sql("SELECT id,parentId,name FROM classes")):
        let id = parseBiggestUInt(row[0])
        result[id] = DbClass(
            id : id, 
            parentId : parseBiggestUInt(row[1]), 
            name : row[2]
        )

iterator instances*() : DbInstance =
    # Iterate all instances from database
    for row in workspace.db.fastRows(sql("SELECT id,classId,name FROM instances")):
        yield DbInstance(
            id : parseBiggestUInt(row[0]), 
            classId : parseBiggestUInt(row[1]),
            name : row[2]
        )
    
proc getAllFields*() : seq[DbField] =
    # Get class and instance fields
    result = newSeq[DbField]()
    for row in workspace.db.fastRows(sql("SELECT id,name,isClassField,classId,valueType FROM fields")):
        let valueIdStr : string = row[5]
        var valueId = 0'u64
        if not valueIdStr.isNil:
            valueId = parseBiggestUInt(valueIdStr)

        result.add(
            DbField(
                id : parseBiggestUInt(row[0]),
                name : row[1],
                isClassField : uint8 parseInt(row[2]),
                classId : parseBiggestUInt(row[3]),
                valueType : uint8 parseInt(row[4]),
                valueId : valueId
            )
        )

iterator values*() : DbValue =
    # Iterate all values

    # Int values
    var query = "SELECT id,instanceId,value FROM v_int ORDER BY id"
    for row in workspace.db.fastRows(sql(query)):
        yield DbIntValue(
            id : parseBiggestUInt(row[0]),
            instanceId : parseBiggestUInt(row[1]),
            value : parseInt(row[2])
        )
    
    # Float values
    query = "SELECT id,instanceId,value FROM v_float ORDER BY id"
    for row in workspace.db.fastRows(sql(query)):
        yield DbFloatValue(
            id : parseBiggestUInt(row[0]),
            instanceId : parseBiggestUInt(row[1]),
            value : parseFloat(row[2])
        )

    # String values
    query = "SELECT id,instanceId,value FROM v_string ORDER BY id"
    for row in workspace.db.fastRows(sql(query)):
        yield DbStringValue(
            id : parseBiggestUInt(row[0]),
            instanceId : parseBiggestUInt(row[1]),
            value : row[2]
        )
    # Entity values
    query = "SELECT id,instanceId,value FROM v_entity ORDER BY id"
    for row in workspace.db.fastRows(sql(query)):
        yield DbEntityValue(
            id : parseBiggestUInt(row[0]),
            instanceId : parseBiggestUInt(row[1]),
            value : parseBiggestUInt(row[2])
        )

proc init*() : void =
    # Init database
    echo "Init database"
    workspace = newWorkspace()
    initDatabase()
    echo "Init database complete"
