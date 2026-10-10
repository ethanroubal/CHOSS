# Export the Lab 3 instruction graphs and def/use lists.
# @category CS6747
# @runtime Jython

import re

from ghidra.app.decompiler import DecompInterface
from ghidra.program.model.lang import Register
from ghidra.program.model.pcode import PcodeOp
from ghidra.program.model.symbol import SourceType


FLAGS = set("cf pf af zf sf tf if df of nt rf ac id iopl vif vip flags eflags rflags".split())
OPERATORS = {PcodeOp.INT_ADD: " + ", PcodeOp.INT_SUB: " - ", PcodeOp.INT_MULT: " * "}
signatures = {}


def address(addr):
    return "0x%x" % addr.getOffset()


def register_at(node):
    return currentProgram.getRegister(node.getAddress(), node.getSize())


def registers(objects):
    names = set()
    for obj in objects:
        if isinstance(obj, Register) and not obj.isProcessorContext():
            name = str(obj.getName()).lower()
            if name != "eip":
                names.add("eflags" if name in FLAGS else name)
    return names


def memory_operand(ins, index):
    # The default representation has no labels or local variable names.
    text = str(ins.getDefaultOperandRepresentation(index)).lower()
    if "[" not in text:
        return None
    expression = "".join(text[text.index("[") + 1:text.rindex("]")].split())
    return "[" + re.sub(r"([-+*])", r" \1 ", expression).strip() + "]"


def storage_locations(storage, argument=False):
    locations = set()
    for node in storage.getVarnodes():
        reg = register_at(node)
        if reg is not None:
            locations |= registers([reg])
        elif argument and node.getAddress().isStackAddress():
            locations.add("[esp]")
        elif node.getAddress().isMemoryAddress():
            locations.add("[" + address(node.getAddress()) + "]")
    return locations


def signature(function):
    # Returns (return locations, argument locations), cached per entry point.
    entry = function.getEntryPoint()
    if entry not in signatures:
        # Default signatures may only be available in the decompiler.
        if not function.isExternal() and function.getSignatureSource() == SourceType.DEFAULT:
            result = decompiler.decompileFunction(function, 30, monitor)
            prototype = result.getHighFunction().getFunctionPrototype()
            parameters = [prototype.getParam(i).getStorage() for i in range(prototype.getNumParams())]
            returns = prototype.getReturnStorage()
        else:
            parameters = [p.getVariableStorage() for p in function.getParameters()]
            returns = function.getReturn().getVariableStorage()
        arguments = set()
        for parameter in parameters:
            arguments |= storage_locations(parameter, argument=True)
        signatures[entry] = storage_locations(returns), arguments
    return signatures[entry]


def call_def_use(ins):
    defs, uses = {"esp"}, {"esp"}
    targets = set(ins.getFlows())
    for ref in ins.getReferencesFrom():
        if ref.getReferenceType().isCall() or ref.getReferenceType().isData():
            targets.add(ref.getToAddress())
    for target in targets:
        function = currentProgram.getFunctionManager().getReferencedFunction(target)
        if function is None:
            continue
        if function.isThunk():
            function = function.getThunkedFunction(True)
        returns, arguments = signature(function)
        defs |= returns
        uses |= arguments
    return defs, uses


def implicit_memory(ins, defs, uses):
    # String instructions can access memory without a written memory operand.
    # Track the symbolic value of each unique varnode to name LOAD/STORE addresses.
    values = {}
    for op in ins.getPcode():
        code = op.getOpcode()
        inputs = []
        for node in op.getInputs():
            reg = register_at(node)
            if node.isConstant():
                inputs.append("0x%x" % node.getOffset())
            elif reg is not None:
                inputs.append(str(reg.getName()).lower())
            else:
                inputs.append(values.get(node))
        if code in (PcodeOp.LOAD, PcodeOp.STORE) and inputs[1] is not None:
            (uses if code == PcodeOp.LOAD else defs).add("[" + inputs[1] + "]")
        output = op.getOutput()
        if output is not None and output.isUnique():
            value = None
            if code in (PcodeOp.COPY, PcodeOp.INT_ZEXT, PcodeOp.INT_SEXT):
                value = inputs[0]
            elif code in OPERATORS and None not in inputs:
                value = inputs[0] + OPERATORS[code] + inputs[1]
            values[output] = value


def def_use(ins):
    mnemonic = str(ins.getMnemonicString()).lower()
    if ins.getFlowType().isCall():
        return call_def_use(ins)
    if mnemonic in ("ret", "retf", "retn"):
        return {"esp"}, {"esp"}
    if mnemonic == "leave":
        return {"ebp", "esp"}, {"ebp", "[ebp]"}
    defs = registers(ins.getResultObjects())
    uses = registers(ins.getInputObjects())
    if mnemonic == "lea":
        return defs, uses
    has_memory_operand = False
    for i in range(ins.getNumOperands()):
        memory = memory_operand(ins, i)
        if memory is None:
            continue
        has_memory_operand = True
        uses |= registers(ins.getOpObjects(i))
        ref = ins.getOperandRefType(i)
        if ref.isWrite():
            defs.add(memory)
        if ref.isRead() or ins.getFlowType().isJump():
            uses.add(memory)
    if mnemonic == "push":
        defs.add("[esp]")
    elif mnemonic == "pop":
        uses.add("[esp]")
    elif not has_memory_operand:
        implicit_memory(ins, defs, uses)
    return defs, uses


def successors(ins):
    targets = set()
    if ins.getFallThrough() is not None:
        targets.add(ins.getFallThrough())
    # Calls go to their continuation; other branches go to their targets.
    if not ins.getFlowType().isCall():
        targets.update(ins.getFlows())
        for ref in ins.getReferencesFrom():
            if ref.getReferenceType().isJump():
                targets.add(ref.getToAddress())
    return sorted(targets, key=lambda a: a.getOffset())


def location_list(locations):
    return " " + ", ".join(sorted(locations)) if locations else ""


def write_function(output, function):
    instructions = list(currentProgram.getListing().getInstructions(function.getBody(), True))
    ids = {ins.getAddress(): "n%d" % (i + 1) for i, ins in enumerate(instructions)}
    output.write('digraph "%s" {\n' % address(function.getEntryPoint()))
    for ins in instructions:
        defs, uses = def_use(ins)
        output.write('%s [label = "%s; D:%s U:%s"];\n' % (
            ids[ins.getAddress()], address(ins.getAddress()), location_list(defs), location_list(uses)))
    for ins in instructions:
        for target in successors(ins):
            if target in ids:
                output.write("%s -> %s;\n" % (ids[ins.getAddress()], ids[target]))
    output.write("}\n\n")


args = getScriptArgs()
if args:
    filename = str(args[0])
elif isRunningHeadless():
    filename = "submission.dot"
else:
    filename = str(askFile("Save submission.dot", "Save").getAbsolutePath())

decompiler = DecompInterface()
decompiler.toggleCCode(False)
decompiler.openProgram(currentProgram)
try:
    with open(filename, "w") as output:
        for function in currentProgram.getFunctionManager().getFunctions(True):
            write_function(output, function)
finally:
    decompiler.dispose()
