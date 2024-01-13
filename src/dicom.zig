const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;
const print = std.debug.print;

const alloc = std.heap.page_allocator;

const PREAMBULA_LENGTH: u16 = 128;
const DICOM_MAGIC_NUMBERS = [_]u8{ 0x44, 0x49, 0x43, 0x4d };
const UNDEFINED_LENGTH = [_]u8{ 0xff, 0xff, 0xff, 0xff };
const SQ_SEQUENCE_DELIMETER = [_]u8{ 0xfe, 0xff, 0xdd, 0xe0, 0x00, 0x00, 0x00, 0x00 };
const SQ_ITEM_TAG = [_]u8{ 0xfe, 0xff, 0x00, 0xe0 };
const SQ_ITEM_DELIMITER = [_]u8{ 0xfe, 0xff, 0x0d, 0xe0, 0x00, 0x00, 0x00, 0x00 };

const IMPLICIT_ENDIAN_TRANSFER_SYNTAX = "1.2.840.10008.1.2";

const bits = struct { first: u8, second: u8, intValue: u8 };
const Tag = struct { Group: [2]u8, Element: [2]u8, VR: [2]u8, Length: u16, Value: []u8 };
const EOFError = error{ EOF, OutOfMemory };
const TagReadingError = error{TagReading};
const Stream = struct {
    data: []const u8,
    index: u64 = 1,
    EOF: bool = false,
    implicit: bool = false,
    metaDataEnded: bool = false,
    fn next8(self: *Stream) !u8 {
        if (self.index + 1 > self.data.len) {
            self.EOF = true;
            return EOFError.EOF;
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

fn getBitAsInt(val: u8) bits {
    const first = val >> 4;
    const second = val & 0x0f;
    return bits{ .first = first, .second = second, .intValue = first * 10 + second };
}

fn printSliceAsChars(slice: []u8) void {
    for (slice) |char| {
        print("{c}", .{char});
    }
    print("\n", .{});
}

fn swapBytesDeletingZeros(i: u32) u32 {
    var swapped = @byteSwap(i);
    while (swapped & 0xff == 0 and swapped != 0) {
        swapped >>= 8;
    }

    return swapped;
}

fn isSQ(vr: [2]u8) bool {
    return vr[0] == 'S' and vr[1] == 'Q';
}

fn isUN(vr: [2]u8) bool {
    return vr[0] == 'U' and vr[1] == 'N';
}

fn isDicomFile(stream: *Stream) !bool {
    for (0..PREAMBULA_LENGTH - 1) |i| {
        _ = i;
        _ = try stream.next8();
    }
    for (DICOM_MAGIC_NUMBERS) |number| {
        if (number != try stream.next8())
            return false;
    }

    print("The file is a DICOM file \n", .{});

    return true;
}

fn readGroup(stream: *Stream) ![2]u8 {
    const group = [_]u8{ try stream.next8(), try stream.next8() };
    print("Group: {x} {x}, ", .{ group[0], group[1] });
    return group;
}

fn readElement(stream: *Stream) ![2]u8 {
    const element = [_]u8{ try stream.next8(), try stream.next8() };
    print("Element: {x} {x}, ", .{ element[0], element[1] });
    return element;
}

fn readVR(stream: *Stream) ![2]u8 {
    const VR = [_]u8{ try stream.next8(), try stream.next8() };

    print("VR: {c}{c}, ", .{ VR[0], VR[1] });

    return VR;
}

fn readLength(stream: *Stream) !u32 {
    var len: u32 = 0;
    for (0..2) |i| {
        _ = i;
        len += try stream.next8();
        len <<= 8;
    }
    len = swapBytesDeletingZeros(len);

    print("Length: {x}, ", .{len});

    return len;
}

fn readImplicitLength(stream: *Stream) !u32 {
    var zeros: u3 = 0;
    var canCount: bool = true;
    var len: u32 = 0;
    for (0..4) |i| {
        if (canCount and stream.data[stream.index] == 0) {
            zeros += 1;
        } else if (stream.data[stream.index] != 0) {
            canCount = false;
        }
        len += try stream.next8();
        if (i < 3)
            len <<= 8;
    }

    len = swapBytesDeletingZeros(len);

    for (0..zeros) |i| {
        _ = i;
        len <<= 8;
    }

    print("EX Length: {x}, ", .{len});

    return len;
}

fn testImplicitVR(transferSyntaxUID: []u8) bool {
    const valuesToTrim = [_]u8{ 0x20, 0x00 };
    const trimmed = mem.trim(u8, transferSyntaxUID, &valuesToTrim);
    if (trimmed.len != IMPLICIT_ENDIAN_TRANSFER_SYNTAX.len) {
        return false;
    }
    for (IMPLICIT_ENDIAN_TRANSFER_SYNTAX, trimmed) |val, syntax| {
        if (val != syntax) {
            return false;
        }
    }

    return true;
}

fn testUndefinedLength(stream: *Stream) !bool {
    for (UNDEFINED_LENGTH, 0..) |val, i| {
        if (val != try stream.next8()) {
            stream.returnBy(i + 1);
            return false;
        }
    }

    return true;
}

fn testSqItemDelimeter(stream: *Stream) !bool {
    for (SQ_ITEM_DELIMITER, 0..) |val, i| {
        if (val != try stream.next8()) {
            stream.returnBy(i + 1);
            return false;
        }
    }

    return true;
}

fn testSequenceDelimeter(stream: *Stream) !bool {
    for (SQ_SEQUENCE_DELIMETER, 0..) |val, i| {
        if (val != try stream.next8()) {
            stream.returnBy(i + 1);
            return false;
        }
    }

    print("Sequence END! \n", .{});

    return true;
}

fn readSQItemTag(stream: *Stream) !bool {
    for (SQ_ITEM_TAG) |val| {
        if (val != try stream.next8()) {
            stream.current();
            return false;
        }
    }

    if (try testUndefinedLength(stream)) {
        while (!try testSqItemDelimeter(stream)) {
            try readTag(stream);
        }
    } else {
        const len = try readImplicitLength(stream);
        print("SQ TAG START WITH LEN: {} \n", .{len});
        const start = stream.index;
        while (stream.index < len + start) {
            try readTag(stream);
        }
    }

    return true;
}

fn readSQLength(stream: *Stream) !bool {
    stream.skipExpRes();
    return try testUndefinedLength(stream);
}

fn readSequence(stream: *Stream) !void {
    if (try readSQLength(stream)) {
        while (!try testSequenceDelimeter(stream)) {
            print("Reading SQ group: \n", .{});
            const res = try readSQItemTag(stream);
            if (!res) print("|No SQ item tag undefied|", .{});
        }
    } else {
        var len = try readImplicitLength(stream);
        const start = stream.index;
        while (stream.index != start + len) {
            print("Reading SQ group: \n", .{});
            const res = try readSQItemTag(stream);
            if (!res) print("|No SQ item tag|", .{});
        }
        print("\n Sequence ended \n", .{});
    }
}

fn readValue(stream: *Stream, len: u64) ![]u8 {
    var value = ArrayList(u8).init(alloc);
    defer value.deinit();
    print(" Value: ", .{});
    for (0..len) |i| {
        _ = i;
        const val = try stream.next8();
        try value.append(val);
        if (len < 1024)
            print("{c}", .{val});
    }
    print("\n", .{});

    return value.toOwnedSlice();
}

fn readTag(stream: *Stream) EOFError!void {
    const group = try readGroup(stream);
    if (group[0] != 2 and !stream.metaDataEnded) {
        stream.metaDataEnded = true;
    }
    const element = try readElement(stream);
    var VR = [_]u8{ 0x00, 0x00 };
    if (!stream.metaDataEnded) {
        VR = try readVR(stream);
    } else if (stream.metaDataEnded and !stream.implicit) {
        VR = try readVR(stream);
    }
    var len: u64 = 0;
    if (stream.implicit and stream.metaDataEnded or VR[0] == 'O' or isUN(VR)) {
        if (VR[0] == 'O' or isUN(VR))
            stream.skipExpRes();
        len = try readImplicitLength(stream);
    } else if (isSQ(VR)) {
        print("\nReading SQ: \n", .{});
        try readSequence(stream);
    } else {
        len = try readLength(stream);
    }
    if (len == 0xffffffff) {
        len = stream.data.len - stream.index;
        print("Fixed length: {} \n", .{len});
    }
    const value = try readValue(stream, len);

    if (group[0] == 2 and group[1] == 0 and element[0] == 0x10 and element[1] == 0) {
        if (testImplicitVR(value)) {
            stream.implicit = true;
        }
    }
}

pub fn main() !void {
    const file = try std.fs.cwd().openFile("./I00007", .{});
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

    if (try isDicomFile(&stream)) {
        print("DICOM START \n", .{});
        while (!stream.EOF) {
            readTag(&stream) catch break;
        }
    }

    print(" \n ENd \n\n", .{});
}
