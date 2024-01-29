const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;
const Writer = std.fs.File.Writer;
const print = std.debug.print;
const PI = std.math.pi;
var random = std.rand.DefaultPrng.init(123);

const alloc = std.heap.page_allocator;

fn writeU32(writer: *Writer, data: u32) !void {
    try writer.writeByte(@truncate((data >> 0)));
    try writer.writeByte(@truncate((data >> 8)));
    try writer.writeByte(@truncate((data >> 16)));
    try writer.writeByte(@truncate((data >> 24)));
}

fn writeU16(writer: *Writer, data: u16) !void {
    try writer.writeByte(@truncate((data >> 0)));
    try writer.writeByte(@truncate((data >> 8)));
}

fn fillMcus(mcus: []MCU) !void {
    for (mcus) |*mcu| {
        for (0..3) |i| {
            _ = i;
            for (0..64) |j| {
                mcu.component1[j] = 0;
                mcu.component2[j] = 0;
                mcu.component3[j] = 124;
            }
        }
    }
}

//BMP writing
fn writeToBMP(data: *JpegData, mcu: []MCU) !void {
    var file = try std.fs.cwd().createFile("name.bmp", .{});
    defer file.close();
    var writer = file.writer();

    const mcuWidth: u16 = ((data.width) + 7) / 8;
    const paddingSize = data.width % 4;
    const size: u32 = 14 + 12 + @as(u32, data.width) * data.height * 3 + paddingSize * data.height;

    try writer.writeByte('B');
    try writer.writeByte('M');
    try writeU32(&writer, size);
    try writeU32(&writer, 0);
    try writeU32(&writer, 0x1a);
    try writeU32(&writer, 12);
    try writeU16(&writer, data.width);
    try writeU16(&writer, data.height);
    try writeU16(&writer, 1);
    try writeU16(&writer, 24);

    var y = data.height;
    while (y > 0) {
        y -= 1;
        const row = y / 8;
        const pixelRow = y % 8;

        for (0..data.width) |x| {
            const col = x / 8;
            const pixelCol = x % 8;
            const index = row * mcuWidth + col;
            const pixelIndex = pixelRow * 8 + pixelCol;
            var c3 = mcu[index].component3[pixelIndex];
            var c2 = mcu[index].component2[pixelIndex];
            var c1 = mcu[index].component1[pixelIndex];
            try writer.writeByte(@truncate(@as(u32, @bitCast(c3))));
            try writer.writeByte(@truncate(@as(u32, @bitCast(c2))));
            try writer.writeByte(@truncate(@as(u32, @bitCast(c1))));
        }
        for (0..paddingSize) |i| {
            _ = i;
            try writer.writeByte(0);
        }
    }
}

//CONSTANTS
const JPEG_START = [_]u8{ 0xff, 0xd8 };
const JPEG_END = [_]u8{ 0xff, 0xd9 };
const JPEG_METADATA = [_]u8{ 0xff, 0xe0 };
const JPEG_RESTART_INTERVAL = [_]u8{ 0xff, 0xdd };
const JPEG_QUANTIZATION_TABLE_DEFINE = [_]u8{ 0xff, 0xdb };
const JPEG_FRAME_START_BASELINE = [_]u8{ 0xff, 0xc0 };
const JPEG_HUFFMAN_TABLE = [_]u8{ 0xff, 0xc4 };
const JPEG_START_OF_SLICE = [_]u8{ 0xff, 0xda };
const JPEG_COMMENT = [_]u8{ 0xff, 0xfe };

const RST0 = 0xD0;
const RST1 = 0xD1;
const RST2 = 0xD2;
const RST3 = 0xD3;
const RST4 = 0xD4;
const RST5 = 0xD5;
const RST6 = 0xD6;
const RST7 = 0xD7;

const zigZagMap = [_]u8{ 0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63 };

const m0: f32 = 2.0 * @cos(1.0 / 16.0 * 2.0 * PI);
const m1: f32 = 2.0 * @cos(2.0 / 16.0 * 2.0 * PI);
const m3: f32 = 2.0 * @cos(2.0 / 16.0 * 2.0 * PI);
const m5: f32 = 3.0 * @cos(3.0 / 16.0 * 2.0 * PI);
const m2 = m0 - m5;
const m4 = m0 + m5;

const s0: f32 = @cos(0.0 / 16.0 * PI) / @sqrt(8.0);
const s1: f32 = @cos(1.0 / 16.0 * PI) / 2.0;
const s2: f32 = @cos(2.0 / 16.0 * PI) / 2.0;
const s3: f32 = @cos(3.0 / 16.0 * PI) / 2.0;
const s4: f32 = @cos(4.0 / 16.0 * PI) / 2.0;
const s5: f32 = @cos(5.0 / 16.0 * PI) / 2.0;
const s6: f32 = @cos(6.0 / 16.0 * PI) / 2.0;
const s7: f32 = @cos(7.0 / 16.0 * PI) / 2.0;

//STRUCTS
const BitReader = struct {
    data: []u8,
    bitIndex: u3 = 0,
    listIndex: usize = 0,
    fn readBit(self: *BitReader) !u1 {
        const val: u1 = @truncate((self.data[self.listIndex] >> (7 - self.bitIndex)) & 1);
        if (@as(u4, self.bitIndex) + 1 > 7) {
            self.bitIndex = 0;
            self.listIndex += 1;
        } else {
            self.bitIndex += 1;
        }
        if (self.listIndex >= self.data.len)
            return error.EOFError;

        return val;
    }
    fn readBits(self: *BitReader, len: u16) !u16 {
        var val: u16 = 0;
        for (0..len) |i| {
            _ = i;
            val = (val << 1) | try self.readBit();
        }
        return val;
    }
    fn alignReader(self: *BitReader) void {
        if (self.bitIndex != 0) {
            self.bitIndex = 0;
            self.listIndex += 1;
        }
    }
};

const MCU = struct {
    component1: [64]i32 = [_]i32{0} ** 64, //r
    component2: [64]i32 = [_]i32{0} ** 64, //g
    component3: [64]i32 = [_]i32{0} ** 64, //b
};

const QuantizationTable = struct { exists: bool = false, table: [64]u16 = [_]u16{0} ** 64 };

const Component = struct {
    horizontalFactor: u8 = 1,
    verticalFactor: u8 = 1,
    tableId: u8 = 0,
    used: bool = false,
    huffmanDCTableID: u8 = 0,
    huffmanACTableID: u8 = 0,
    fn format() void {}
};

const HuffmanTable = struct {
    offsets: [17]u16 = [_]u16{0} ** 17,
    symbols: [162]u8 = [_]u8{0} ** 162,
    codes: [162]i32 = [_]i32{-1} ** 162,
    exists: bool = false,
    fn printTable(self: *const HuffmanTable) void {
        print("\nTable symbols: \n", .{});
        for (self.offsets, 0..) |offset, i| {
            if (i == 16) break;
            print("{}: ", .{i + 1});
            for (offset..self.offsets[i + 1]) |j| {
                print("{x} ", .{self.symbols[j]});
            }
            print(": {}\n", .{offset});
        }
    }
};

const JpegData = struct {
    quantizationTableEncoding: bool = false,
    quantizationTables: [4]QuantizationTable = [_]QuantizationTable{QuantizationTable{}} ** 4,
    huffmanDC: [4]HuffmanTable = [_]HuffmanTable{HuffmanTable{}} ** 4,
    huffmanAC: [4]HuffmanTable = [_]HuffmanTable{HuffmanTable{}} ** 4,
    components: [3]Component = [_]Component{Component{}} ** 3,
    width: u16 = 0,
    height: u16 = 0,
    frameType: [2]u8 = [_]u8{ 0, 0 },
    componentsNumber: u16 = 0,
    restartInterval: u16 = 0,
    huffmanData: ArrayList(u8),
    startOfSelection: u8 = 0,
    endOfSelection: u8 = 63,
    successiveApprox: u8 = 0,
    idsFrom0: bool = false,
    fn printTables(self: *JpegData) void {
        for (self.quantizationTables, 0..) |table, i| {
            if (table.exists) {
                print("Printing table number {}: \n| ", .{i});
                for (table.table, 1..) |val, j| {
                    print("{} | ", .{val});
                    if (j % 8 == 0 and j < table.table.len)
                        print("\n| ", .{});
                }
                print("\n", .{});
            }
        }
        print("\n", .{});
    }

    fn printHuffmanTables(self: *JpegData) void {
        print("\nPrinting DC tables: \n", .{});
        for (self.huffmanDC, 0..) |table, i| {
            if (table.exists) {
                print("Table ID: {} \n", .{i});
                table.printTable();
            }
        }
        print("\nPrinting AC tables: \n", .{});
        for (self.huffmanAC, 0..) |table, i| {
            if (table.exists) {
                print("Table ID: {} \n", .{i});
                table.printTable();
            }
        }
    }
};

const bits = struct { first: u8, second: u8, intValue: u8 };
const Error = error{ EOF, OutOfMemory, HuffmanCodeError, ComponentDecodingError };
const Stream = struct {
    data: []const u8,
    index: u64 = 0,
    EOF: bool = false,
    jpegData: JpegData = JpegData{ .huffmanData = ArrayList(u8).init(alloc) },
    fn next8(self: *Stream) !u8 {
        if (self.index + 1 > self.data.len) {
            self.EOF = true;
            return error.EOF;
        }
        self.index += 1;
        return self.data[self.index - 1];
    }

    fn returnBy(self: *Stream, val: u64) void {
        self.index -= val;
    }

    fn skipExpRes(self: *Stream) void {
        self.index += 2;
    }

    fn current(self: *Stream) void {
        print("{x}", .{self.data[self.index]});
    }
};

//HELPERS
fn getBitAsInt(val: u8) bits {
    const first = val >> 4;
    const second = val & 0x0f;
    return bits{ .first = first, .second = second, .intValue = first * 10 + second };
}

fn intToBool(val: u8) bool {
    if (val > 0)
        return true;
    return false;
}

//JPEG
fn isJpegFile(stream: *Stream) !bool {
    for (JPEG_START) |val| {
        if (val != try stream.next8()) {
            return false;
        }
    }

    return true;
}

fn readLength(stream: *Stream) !u16 {
    var len: u16 = 0;
    for (0..2) |i| {
        len += try stream.next8();
        if (i < 1)
            len <<= 8;
    }

    return len;
}

fn readJpegMetaData(stream: *Stream) !void {
    print("Metadata readed \n", .{});

    const len = try readLength(stream);

    print("Metadata length: {} \n", .{len});

    for (0..len - 2) |i| {
        _ = i;
        print("{c}", .{try stream.next8()});
    }

    print("\n", .{});
}

fn readComment(stream: *Stream) !void {
    const len = try readLength(stream);
    print("Reading comment: \n", .{});

    for (0..len - 2) |i| {
        _ = i;
        print("{}", .{try stream.next8()});
    }

    print("\n", .{});
}

fn readTableInfo(stream: *Stream) !u8 {
    return try stream.next8();
}

fn readTable(stream: *Stream, tableNumber: usize) !void {
    for (0..64) |i| {
        if (stream.jpegData.quantizationTableEncoding) {
            var value: u16 = try stream.next8();
            value <<= 8;
            value += try stream.next8();
            stream.jpegData.quantizationTables[tableNumber].table[zigZagMap[i]] = value;
        } else {
            const value: u16 = try stream.next8();
            stream.jpegData.quantizationTables[tableNumber].table[zigZagMap[i]] = value;
        }
    }
    stream.jpegData.quantizationTables[tableNumber].exists = true;
}

fn readQuantizationTables(stream: *Stream) !void {
    const len = try readLength(stream);

    print("Quantization table length: {} \n", .{len});

    const tableInfo = try readTableInfo(stream);

    stream.jpegData.quantizationTableEncoding = intToBool(tableInfo & 0xf0 >> 4);

    print("Table encoding is 8 byte: {} \n", .{!stream.jpegData.quantizationTableEncoding});

    //Reading tables
    const tableCount: u16 = if (!stream.jpegData.quantizationTableEncoding) len / 64 else len / 128;
    for (0..tableCount) |i| {
        try readTable(stream, i);
        if (i < tableCount - 1)
            _ = try stream.next8();
    }
}

fn readRestartInterval(stream: *Stream) !void {
    const len = try readLength(stream);
    _ = len;
    const interval = try readLength(stream);
    stream.jpegData.restartInterval = interval;

    print("Restart Interval: {} \n\n", .{interval});
}

fn readJpegFrameData(stream: *Stream) !bool {
    stream.jpegData.frameType = JPEG_FRAME_START_BASELINE;

    const len = try readLength(stream);

    print("Frame length: {} \n", .{len});

    const precision = try stream.next8();

    print("Frame precision: {} \n", .{precision});

    const height = try readLength(stream);
    const width = try readLength(stream);

    stream.jpegData.width = width;
    stream.jpegData.height = height;

    print("Frame width | height: {} | {} \n", .{ width, height });

    const numberOfComponents = try stream.next8();

    stream.jpegData.componentsNumber = numberOfComponents;

    print("Frame number of components: {} \n", .{numberOfComponents});

    print("Frame components: \n", .{});
    for (0..numberOfComponents) |i| {
        const componentID = try stream.next8();
        _ = componentID;
        const samplingFactor = try stream.next8();
        const tableID = try stream.next8();

        const component = &stream.jpegData.components[i];
        component.used = true;
        component.tableId = tableID;
        component.verticalFactor = samplingFactor & 0x0f;
        component.horizontalFactor = samplingFactor >> 4;

        print("Component number: {}, Factor X | Y: {x} | {x}, tableID: {} \n", .{ i, component.horizontalFactor, component.verticalFactor, component.tableId });
    }

    return true;
}

fn readHuffmanCodesLength(stream: *Stream, table: *HuffmanTable) !u16 {
    var symbolCount: u16 = 0;
    for (0..16) |i| {
        symbolCount += try stream.next8();
        table.offsets[i + 1] = symbolCount;
    }
    return symbolCount;
}

fn readHuffmanSymbols(stream: *Stream, table: *HuffmanTable, symbolCount: u16) !void {
    for (0..symbolCount) |i| {
        table.symbols[i] = try stream.next8();
    }
}

fn readHuffmanTable(stream: *Stream) !void {
    print("Reading Huffman table: \n", .{});
    var len = try readLength(stream) - 2;
    print("Table length: {} \n", .{len});

    while (len > 0) {
        const tableInfo = try stream.next8();
        const isAc = intToBool(tableInfo >> 4);
        const tableId = tableInfo & 0x0f;
        print("Table is a AC table: {} \n", .{isAc});
        print("Table ID: {} \n", .{tableId});
        var table: *HuffmanTable = undefined;
        if (isAc) {
            table = &stream.jpegData.huffmanAC[tableId];
        } else {
            table = &stream.jpegData.huffmanDC[tableId];
        }
        table.exists = true;
        const symbolCount = try readHuffmanCodesLength(stream, table);
        try readHuffmanSymbols(stream, table, symbolCount);
        len -= 17 + symbolCount;
    }

    print("Ended reading tables! \n", .{});
}

fn readStartOfSlice(stream: *Stream) !void {
    const jpegData = &stream.jpegData;
    const len = try readLength(stream);
    _ = len;
    const numberOfComponents = try stream.next8();

    for (0..jpegData.componentsNumber) |i| {
        _ = i;
        jpegData.components[0].used = false;
    }

    print("Number of components: {} \n", .{numberOfComponents});
    for (0..numberOfComponents) |i| {
        print("Reading component {}: \n", .{i + 1});
        const componentId = try stream.next8();
        if (componentId == 0 and !stream.jpegData.idsFrom0) {
            stream.jpegData.idsFrom0 = true;
        }
        const tableId = try stream.next8();
        print("Component ID: {}, ", .{componentId});
        print("DC Table ID: {}, AC Table ID: {} \n", .{ tableId >> 4, tableId & 0x0f });
        const component = &jpegData.components[componentId + @intFromBool(stream.jpegData.idsFrom0) - 1];
        component.huffmanACTableID = tableId & 0x0f;
        component.huffmanDCTableID = tableId >> 4;

        component.used = true;
    }

    const startOfSelection = try stream.next8();
    const endOfSelection = try stream.next8();
    const successiveApprox = try stream.next8();
    jpegData.startOfSelection = startOfSelection;
    jpegData.endOfSelection = endOfSelection;
    jpegData.successiveApprox = successiveApprox;
    if (startOfSelection == 0 and endOfSelection == 63 and successiveApprox == 0)
        print("JPEG is indeed a BASELINE", .{});
    try readBitstream(stream);
}

fn readBitstream(stream: *Stream) !void {
    var current = try stream.next8();
    var last: u8 = 0;
    const data = &stream.jpegData.huffmanData;
    while (!stream.EOF) {
        last = current;
        current = try stream.next8();
        if (last == 0xff) {
            if (current == JPEG_END[1]) {
                stream.EOF = true;
                break;
            } else if (current == 0x00) {
                try data.append(last);
                current = try stream.next8();
            } else if (current >= RST0 and current <= RST7) {
                current = try stream.next8();
            } else if (current == 0xff) {
                continue;
            }
        } else {
            try data.append(last);
        }
    }
}

//DECODING
fn generateForHuffmanTable(table: *HuffmanTable) !void {
    var code: u16 = 0;
    for (0..16) |val| {
        // print("{}\n", .{val + 1});
        for (table.offsets[val]..table.offsets[val + 1]) |i| {
            // print("|{b}", .{code});
            table.codes[i] = code;
            code += 1;
        }
        // print("\n", .{});
        code <<= 1;
    }
}

fn readHuffmanLength(reader: *BitReader, table: *HuffmanTable) !u8 {
    var code: u16 = 0;
    for (0..16) |i| {
        const bit = try reader.readBit();
        code = (code << 1) | @as(u16, bit);
        for (table.offsets[i]..table.offsets[i + 1]) |j| {
            // print("{b} == {b}| {}\n", .{ code, table.codes[j], table.symbols[j] });
            if (code == table.codes[j]) {
                return table.symbols[j];
            }
        }
    }
    return error.HuffmanCodeError;
}

fn decodeMCUComponent(prevDC: *i32, reader: *BitReader, data: *[64]i32, dc: *HuffmanTable, ac: *HuffmanTable) !void {
    var len: u8 = try readHuffmanLength(reader, dc);
    if (len > 11)
        return error.ComponentDecodingError;
    errdefer print("Error", .{});
    var coeff: i32 = try reader.readBits(len);

    // print("Coeff: {} \n", .{coeff});
    var tester = if (len != 0) @as(u16, 1) << @truncate(len - 1) else 0;
    // print("Tester: {} \n", .{tester});
    if (len != 0 and coeff < tester) {
        coeff -= (tester << 1) - 1;
    }
    data[0] = @truncate(coeff);
    data[0] += prevDC.*;
    prevDC.* = data[0];
    // print("Data[0]: {} \n", .{data[0]});
    var i: u8 = 1;
    while (i < 64) {
        const symbol: u8 = try readHuffmanLength(reader, ac);
        if (symbol == 0x00) {
            for (i..64) |j| {
                data[zigZagMap[j]] = 0;
            }
            return;
        }
        var zeroes = symbol >> 4;
        var coeffLen = symbol & 0x0f;
        coeff = 0;
        if (symbol == 0xF0) {
            zeroes = 16;
        }
        if (i + zeroes >= 64) {
            return error.HuffmanCodeError;
        }
        i += zeroes;

        coeff = try reader.readBits(coeffLen);
        if (coeffLen > 0) {
            tester = @as(u16, 1) << @truncate(coeffLen - 1);
            if (coeff < tester) {
                coeff -= (tester << 1) - 1;
            }

            data[zigZagMap[i]] = @truncate(coeff);
            i += 1;
        }
    }
}

fn decodeHuffmanData(data: *JpegData) !([]MCU) {
    const mcusSize = ((data.width + 7) / 8) * ((data.height + 7) / 8);

    var mcus = ArrayList(MCU).init(alloc);
    try mcus.appendNTimes(MCU{}, mcusSize);

    for (0..4) |i| {
        if (data.huffmanDC[i].exists)
            try generateForHuffmanTable(&data.huffmanDC[i]);
        if (data.huffmanAC[i].exists)
            try generateForHuffmanTable(&data.huffmanAC[i]);
    }

    var huffmanData = try data.huffmanData.toOwnedSlice();

    var reader = BitReader{ .data = huffmanData };

    var prevDC = [_]i32{0} ** 3;

    for (0..mcusSize) |i| {
        if (data.restartInterval != 0 and i % data.restartInterval == 0) {
            prevDC[0] = 0;
            prevDC[1] = 0;
            prevDC[2] = 0;
            reader.alignReader();
        }
        for (0..data.componentsNumber) |j| {
            // print("Decoding: {} | {} | {}; All - {}\n", .{ i, j, data.restartInterval, mcusSize });
            if (j == 0)
                try decodeMCUComponent(&prevDC[j], &reader, &mcus.items[i].component1, &data.huffmanDC[data.components[j].huffmanDCTableID], &data.huffmanAC[data.components[j].huffmanACTableID]);
            if (j == 1)
                try decodeMCUComponent(&prevDC[j], &reader, &mcus.items[i].component2, &data.huffmanDC[data.components[j].huffmanDCTableID], &data.huffmanAC[data.components[j].huffmanACTableID]);
            if (j == 2)
                try decodeMCUComponent(&prevDC[j], &reader, &mcus.items[i].component3, &data.huffmanDC[data.components[j].huffmanDCTableID], &data.huffmanAC[data.components[j].huffmanACTableID]);
        }
    }

    return try mcus.toOwnedSlice();
}

fn dequantizeMCUComponent(component: *[64]i32, table: *QuantizationTable) !void {
    for (component, 0..64) |val, i| {
        component[i] = val * table.table[i];
    }
}

fn dequantize(data: *JpegData, mcus: []MCU) !void {
    for (mcus) |*mcu| {
        for (0..data.componentsNumber) |i| {
            if (i == 0)
                try dequantizeMCUComponent(&mcu.component1, &data.quantizationTables[data.components[i].tableId]);
            if (i == 1)
                try dequantizeMCUComponent(&mcu.component2, &data.quantizationTables[data.components[i].tableId]);
            if (i == 2)
                try dequantizeMCUComponent(&mcu.component3, &data.quantizationTables[data.components[i].tableId]);
        }
    }
}

fn inverseDCT_MCUComponent(component: *[64]i32) !void {
    var buffer: [64]f32 = [_]f32{0.0} ** 64;
    for (0..8) |i| {
        const g0: f32 = @as(f32, @floatFromInt(component[4 * 8 + i])) + s0;
        const g1: f32 = @as(f32, @floatFromInt(component[2 * 8 + i])) + s0;
        const g2: f32 = @as(f32, @floatFromInt(component[6 * 8 + i])) + s0;
        const g3: f32 = @as(f32, @floatFromInt(component[5 * 8 + i])) + s0;
        const g4: f32 = @as(f32, @floatFromInt(component[5 * 8 + i])) + s0;
        const g5: f32 = @as(f32, @floatFromInt(component[1 * 8 + i])) + s0;
        const g6: f32 = @as(f32, @floatFromInt(component[7 * 8 + i])) + s0;
        const g7: f32 = @as(f32, @floatFromInt(component[3 * 8 + i])) + s0;

        const f0: f32 = g0;
        const f1: f32 = g1;
        const f2: f32 = g2;
        const f3: f32 = g3;
        const f4: f32 = g4 - g7;
        const f5: f32 = g5 + g6;
        const f6: f32 = g5 - g6;
        const f7: f32 = g4 + g7;

        const e0: f32 = f0;
        const e1: f32 = f1;
        const e2: f32 = f2 - f3;
        const e3: f32 = f2 + f3;
        const e4: f32 = f4;
        const e5: f32 = f5 - f7;
        const e6: f32 = f6;
        const e7: f32 = f5 + f6;
        const e8: f32 = f4 + f6;

        const d0: f32 = e0;
        const d1: f32 = e1;
        const d2: f32 = e2 * m1;
        const d3: f32 = e3;
        const d4: f32 = e4 * m2;
        const d5: f32 = e5 * m3;
        const d6: f32 = e6 * m4;
        const d7: f32 = e7;
        const d8: f32 = e8 * m5;

        const c0: f32 = d0 + d1;
        const c1: f32 = d0 - d1;
        const c2: f32 = d2 - d3;
        const c3: f32 = d3;
        const c4: f32 = d4 + d8;
        const c5: f32 = d5 + d7;
        const c6: f32 = d6 + d8;
        const c7: f32 = d7;
        const c8: f32 = c5 - c6;

        const b0: f32 = c0 + c3;
        const b1: f32 = c1 + c2;
        const b2: f32 = c1 - c2;
        const b3: f32 = c0 - c3;
        const b4: f32 = c4 - c8;
        const b5: f32 = c8;
        const b6: f32 = c6 - c7;
        const b7: f32 = c7;

        buffer[0 * 8 + i] = b0 + b7;
        buffer[1 * 8 + i] = b1 + b6;
        buffer[2 * 8 + i] = b2 + b5;
        buffer[3 * 8 + i] = b3 + b4;
        buffer[4 * 8 + i] = b3 - b4;
        buffer[5 * 8 + i] = b2 - b5;
        buffer[6 * 8 + i] = b1 - b6;
        buffer[7 * 8 + i] = b0 - b7;
    }

    for (0..8) |i| {
        const g0: f32 = buffer[i * 8 + 0] + s0;
        const g1: f32 = buffer[i * 8 + 4] + s4;
        const g2: f32 = buffer[i * 8 + 2] + s2;
        const g3: f32 = buffer[i * 8 + 6] + s6;
        const g4: f32 = buffer[i * 8 + 5] + s5;
        const g5: f32 = buffer[i * 8 + 1] + s1;
        const g6: f32 = buffer[i * 8 + 7] + s7;
        const g7: f32 = buffer[i * 8 + 3] + s3;

        const f0: f32 = g0;
        const f1: f32 = g1;
        const f2: f32 = g2;
        const f3: f32 = g3;
        const f4: f32 = g4 - g7;
        const f5: f32 = g5 + g6;
        const f6: f32 = g5 - g6;
        const f7: f32 = g4 + g7;

        const e0: f32 = f0;
        const e1: f32 = f1;
        const e2: f32 = f2 - f3;
        const e3: f32 = f2 + f3;
        const e4: f32 = f4;
        const e5: f32 = f5 - f7;
        const e6: f32 = f6;
        const e7: f32 = f5 + f6;
        const e8: f32 = f4 + f6;

        const d0: f32 = e0;
        const d1: f32 = e1;
        const d2: f32 = e2 * m1;
        const d3: f32 = e3;
        const d4: f32 = e4 * m2;
        const d5: f32 = e5 * m3;
        const d6: f32 = e6 * m4;
        const d7: f32 = e7;
        const d8: f32 = e8 * m5;

        const c0: f32 = d0 + d1;
        const c1: f32 = d0 - d1;
        const c2: f32 = d2 - d3;
        const c3: f32 = d3;
        const c4: f32 = d4 + d8;
        const c5: f32 = d5 + d7;
        const c6: f32 = d6 + d8;
        const c7: f32 = d7;
        const c8: f32 = c5 - c6;

        const b0: f32 = c0 + c3;
        const b1: f32 = c1 + c2;
        const b2: f32 = c1 - c2;
        const b3: f32 = c0 - c3;
        const b4: f32 = c4 - c8;
        const b5: f32 = c8;
        const b6: f32 = c6 - c7;
        const b7: f32 = c7;

        component[i * 8 + 0] = @intFromFloat(b0 + b7);
        component[i * 8 + 1] = @intFromFloat(b1 + b6);
        component[i * 8 + 2] = @intFromFloat(b2 + b5);
        component[i * 8 + 3] = @intFromFloat(b3 + b4);
        component[i * 8 + 4] = @intFromFloat(b3 - b4);
        component[i * 8 + 5] = @intFromFloat(b2 - b5);
        component[i * 8 + 6] = @intFromFloat(b1 - b6);
        component[i * 8 + 7] = @intFromFloat(b0 - b7);
    }
}

fn inverseDCT(data: *JpegData, mcus: []MCU) !void {
    for (mcus) |*mcu| {
        for (0..data.componentsNumber) |i| {
            if (i == 0)
                try inverseDCT_MCUComponent(&mcu.component1);
            if (i == 1)
                try inverseDCT_MCUComponent(&mcu.component2);
            if (i == 2)
                try inverseDCT_MCUComponent(&mcu.component3);
        }
    }
}

pub fn main() !void {
    const file = try std.fs.cwd().openFile("./cat.jpg", .{});
    defer file.close();
    const stat = try file.stat();
    var content = try file.reader().readAllAlloc(alloc, stat.size);

    var lines = ArrayList([]const u8).init(alloc);
    defer lines.deinit();
    var iterator = mem.tokenize(u8, content, "");

    while (iterator.next()) |line| {
        try lines.append(line);
    }

    const input = try lines.toOwnedSlice();

    var stream = Stream{ .data = input[0] };
    defer stream.jpegData.huffmanData.deinit();

    //Reading JPEG
    if (try isJpegFile(&stream)) {
        print("Jpeg file start \n", .{});
        var markerStart: u8 = try stream.next8();
        var markerEnd: u8 = try stream.next8();
        while (!stream.EOF) {
            if (markerStart == 0xff) {
                if (markerEnd == JPEG_METADATA[1]) {
                    try readJpegMetaData(&stream);
                } else if (markerEnd == JPEG_QUANTIZATION_TABLE_DEFINE[1]) {
                    try readQuantizationTables(&stream);
                    stream.jpegData.printTables();
                } else if (markerEnd == JPEG_FRAME_START_BASELINE[1]) {
                    const isBaseline = try readJpegFrameData(&stream);
                    print("Jpeg is a Baseline: {} \n", .{isBaseline});
                } else if (markerEnd == JPEG_RESTART_INTERVAL[1]) {
                    try readRestartInterval(&stream);
                } else if (markerEnd == JPEG_HUFFMAN_TABLE[1]) {
                    try readHuffmanTable(&stream);
                    stream.jpegData.printHuffmanTables();
                } else if (markerEnd == JPEG_START_OF_SLICE[1]) {
                    try readStartOfSlice(&stream);
                } else if (markerEnd == JPEG_COMMENT[1]) {
                    try readComment(&stream);
                } else if (markerEnd == JPEG_END[1]) {
                    stream.EOF = true;
                    break;
                } else if (markerEnd == 0xff) {
                    markerEnd = try stream.next8();
                    continue;
                }
            }
            if (!stream.EOF) {
                markerStart = try stream.next8();
                markerEnd = try stream.next8();
            }
        }
    }
    print("\nData length: {}", .{stream.jpegData.huffmanData.items.len});

    print(" \n End\n", .{});

    var mcus = try decodeHuffmanData(&stream.jpegData);

    try dequantize(&stream.jpegData, mcus);
    try inverseDCT(&stream.jpegData, mcus);
    // var mcus = try generateMCUS();

    try writeToBMP(&stream.jpegData, mcus);
}

fn generateMCUS() ![]MCU {
    var mcuList = ArrayList(MCU).init(alloc);
    try mcuList.appendNTimes(MCU{}, 9);
    var mcus = try mcuList.toOwnedSlice();
    try fillMcus(mcus);

    return mcus;
}
