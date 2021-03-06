import
    strutils,
    tables,
    streams,
    asyncdispatch,
    asyncfile,
    ../../shared/valuePacker,
    entityProducer,
    dataLogger,
    database

#############################################################################################
# Workspace of storage
type Workspace = ref object
    classes : TableRef[BiggestUInt, Class]                    # All classes
    instances : TableRef[BiggestUInt, Instance]               # All instances
    fields : TableRef[BiggestUInt, Field]                     # All fields

var workspace {.threadvar.} : Workspace

proc newWorkspace() : Workspace =
    # Create new workspace
    result = Workspace()
    result.classes = newTable[BiggestUInt, Class]()
    result.instances = newTable[BiggestUInt, Instance]()
    result.fields = newTable[BiggestUInt, Field]()

#############################################################################################
# Private

# Forward declaration
proc getClassById*(id : BiggestUInt) : Class
proc getInstanceById*(id : BiggestUInt) : Instance

proc placeToDatabase() : void =        
    # Place all log to database
    database.beginTransaction()
    for record in dataLogger.allRecords():
        database.writeLogRecord(record)        
    database.commit()
    dataLogger.removeLog()
    #echo "All log placed to database"

proc getClass(classTable : TableRef[BiggestUInt, DbClass], id : BiggestUInt) : Class =
    # Get class from class table with all parents
    let cls = classTable.getOrDefault(id)
    if cls.isNil: return nil
    result = entityProducer.newClass(id, cls.name, getClass(classTable, cls.parentId))

proc loadFromDatabase() : void =
    # Load all from database to memory
    let classes = database.getAllClasses()
    for k, v in classes:
        workspace.classes[v.id] = getClass(classes, v.id)

    # Load all instances to memory
    for i in database.instances():
        let class = getClassById(i.classId)
        if class.isNil: raise newException(Exception, "Class not found for instance $1" % $(i.id))
        workspace.instances[i.id] = entityProducer.newInstance(i.id, i.name, class)

    # Load all fields to memory
    let fields = database.getAllFields()    
    for f in fields:
        let class = getClassById(f.classId)
        if class.isNil: continue
        if f.isClassField:
            let field = entityProducer.newField(f.id, f.name, class, true, f.valueType)
            class.classFields.add(field)
        else:
            let field = entityProducer.newField(f.id, f.name, class, false, f.valueType)
            class.instanceFields.add(field)

    # Load values to memory, except blobs
    
    #echo "All data loaded from database"

#############################################################################################
# Public interface

iterator allClasses*() : Class =
    # Iterate all classes
    for k, v in workspace.classes:
        yield v
    yield nil

iterator allInstances*() : Instance =
    # Iterate all instances
    for k, v in workspace.instances:        
        yield v
    yield nil

proc storeNewClass*(class : Class) : Future[void] {.async.} =
    # Store new class data
    var parentId = 0'u64
    if not class.parent.isNil:
        parentId = class.parent.id

    var record = dataLogger.AddClassRecord(
        id : class.id,
        name : class.name, 
        parentId : parentId
    )
    await dataLogger.logNewClass(record)

    workspace.classes[class.id] = class

proc storeNewInstance*(instance : Instance) : Future[void] {.async.} =
    # Store new instance data
    var record = dataLogger.AddInstanceRecord(
        id : instance.id,
        classId : instance.class.id,
        name : instance.name
    )
    await dataLogger.logNewInstance(record)
    workspace.instances[instance.id] = instance

proc storeNewField*(field : Field) : Future[void] {.async.} =
    # Store new class field data

    var record = dataLogger.AddFieldRecord(
        id : field.id,
        name : field.name,
        isClassField : true,
        classId : field.class.id
    )
    await dataLogger.logNewField(record)
    field.class.classFields.add(field)
    workspace.fields[field.id] = field

proc getClassById*(id : BiggestUInt) : Class =
    # Get class by id
    result = workspace.classes.getOrDefault(id)

proc getInstanceById*(id : BiggestUInt) : Instance =
    # Get instance by id
    result = workspace.instances.getOrDefault(id)

proc getFieldById*(id : BiggestUInt) : Field =
    # Get field by id
    result = workspace.fields.getOrDefault(id)

proc getFieldValue*(field : Field) : Value = 
    # Return field value of class
    result = field.class.values.getOrDefault(field.id)

proc getFieldValue*(field : Field, instance : Instance) : Value =
    # Return field value of instance
    result = instance.values.getOrDefault(field.id)

proc setFieldValue*(field : Field, value : Value) : void =
    # Set field value
    #dataLogger.logNewValue()
    #workspace.values[field.id].value = value
    discard

proc init*() {.async.} =
    # Init storage
    #echo "Initing storage"
    workspace = newWorkspace()
    dataLogger.init()
    await database.init()
    placeToDatabase()
    loadFromDatabase()
    #echo "Init storage complete"