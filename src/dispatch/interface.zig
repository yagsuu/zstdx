//! borrowed instance/vtable bindings

const std = @import("std");

const thunk = @import("thunk.zig");

pub fn Interface(comptime Contract: type) type {
    comptime Impl.requireContract(Contract);

    return struct {
        const Self = @This();

        pub fn bind(provider: anytype) Contract {
            return Self.bindWith(provider, .{});
        }

        pub fn bindWith(provider: anytype, comptime overrides: anytype) Contract {
            const Binding = Impl.Binding(Contract, @TypeOf(provider), overrides);

            return .{
                .instance = @ptrCast(provider),
                .vtable = &Binding.vtable,
            };
        }
    };
}

const Impl = struct {
    fn requireContract(comptime Contract: type) void {
        if (@typeInfo(Contract) != .@"struct") {
            @compileError("Interface: contract must be a struct");
        }

        if (!@hasField(Contract, "instance") or
            !@hasField(Contract, "vtable") or
            !@hasDecl(Contract, "Vtable"))
        {
            @compileError("Interface: contract must declare instance, vtable, and Vtable");
        }

        const Instance = @FieldType(Contract, "instance");
        if (Instance != *anyopaque and Instance != *const anyopaque) {
            @compileError("Interface: instance must be *anyopaque or *const anyopaque");
        }

        if (@TypeOf(Contract.Vtable) != type or @typeInfo(Contract.Vtable) != .@"struct") {
            @compileError("Interface: Vtable must be a struct type");
        }

        if (@FieldType(Contract, "vtable") != *const Contract.Vtable) {
            @compileError("Interface: vtable must be *const Vtable");
        }

        const vtable = @typeInfo(Contract.Vtable).@"struct";

        for (vtable.field_names, vtable.field_types) |name, FieldType| {
            requireOperation(Instance, name, FieldType);
        }
    }

    fn OpPtr(comptime Slot: type) type {
        return switch (@typeInfo(Slot)) {
            .optional => |optional| optional.child,
            else => Slot,
        };
    }

    fn requireOperation(
        comptime Instance: type,
        comptime name: []const u8,
        comptime Pointer: type,
    ) void {
        const label = "Interface: operation '" ++ name ++ "'";
        const pointer = switch (@typeInfo(OpPtr(Pointer))) {
            .pointer => |p| p,
            else => @compileError(label ++ ": expected a const function pointer"),
        };

        if (pointer.size != .one or !pointer.attrs.@"const") {
            @compileError(label ++ ": expected a const function pointer");
        }

        const signature = functionInfo(pointer.child, label);
        if (signature.param_types.len == 0 or signature.param_types.len > 4) {
            @compileError(label ++ ": expected a receiver and zero through three arguments");
        }

        const Receiver = signature.param_types[0].?;
        if (Receiver != *anyopaque and Receiver != *const anyopaque) {
            @compileError(label ++ ": receiver must be *anyopaque or *const anyopaque");
        }

        if (Instance == *const anyopaque and Receiver != *const anyopaque) {
            @compileError(label ++ ": a read-only contract requires a const receiver");
        }
    }

    fn Binding(
        comptime Contract: type,
        comptime Pointer: type,
        comptime overrides: anytype,
    ) type {
        const pointer = switch (@typeInfo(Pointer)) {
            .pointer => |p| p,
            else => @compileError("Interface.bind: provider must be a single-item pointer to a struct"),
        };

        if (pointer.size != .one or @typeInfo(pointer.child) != .@"struct") {
            @compileError("Interface.bind: provider must be a single-item pointer to a struct");
        }

        if (Pointer != *pointer.child and Pointer != *const pointer.child) {
            @compileError("Interface.bind: provider must be an unqualified mutable or const pointer");
        }

        if (pointer.attrs.@"const" and @FieldType(Contract, "instance") == *anyopaque) {
            @compileError("Interface.bind: const provider cannot implement a mutable contract");
        }

        const Provider = pointer.child;

        if (@typeInfo(@TypeOf(overrides)) != .@"struct") {
            @compileError("Interface.bindWith: overrides must be a struct");
        }

        for (@typeInfo(@TypeOf(overrides)).@"struct".field_names) |name| {
            if (!@hasField(Contract.Vtable, name)) {
                @compileError("Interface.bindWith: unknown operation '" ++ name ++ "'");
            }
        }

        return struct {
            const vtable: Contract.Vtable = blk: {
                var result: Contract.Vtable = undefined;

                const vtable_info = @typeInfo(Contract.Vtable).@"struct";

                for (vtable_info.field_names, vtable_info.field_types) |name, FieldType| {
                    const overridden = @hasField(@TypeOf(overrides), name);
                    const optional = @typeInfo(FieldType) == .optional;

                    if (!overridden and !@hasDecl(Provider, name)) {
                        if (!optional) {
                            @compileError("Interface: operation '" ++ name ++ "': missing provider method");
                        }

                        @field(result, name) = null;
                        continue;
                    }

                    const operation = if (overridden)
                        @field(overrides, name)
                    else
                        @field(Provider, name);

                    if (@TypeOf(operation) == @TypeOf(null)) {
                        if (!optional) {
                            @compileError(
                                "Interface: operation '" ++ name ++ "': required operation cannot be null",
                            );
                        }

                        @field(result, name) = null;
                        continue;
                    }

                    const Adapter = Impl.Method(
                        Provider,
                        name,
                        OpPtr(FieldType),
                        operation,
                    );

                    @field(result, name) = &Adapter.call;
                }

                break :blk result;
            };
        };
    }

    fn functionInfo(comptime Function: type, comptime label: []const u8) std.builtin.Type.Fn {
        const signature = thunk.functionInfo(Function, label);

        if (signature.attrs.@"callconv" != .auto) {
            @compileError(label ++ ": expected the default Zig calling convention");
        }

        return signature;
    }

    fn methodInfo(
        comptime Provider: type,
        comptime name: []const u8,
        comptime Signature: type,
        comptime operation: anytype,
    ) std.builtin.Type.Fn {
        const Function = switch (@typeInfo(@TypeOf(operation))) {
            .pointer => |pointer| pointer.child,
            else => @TypeOf(operation),
        };

        const label = "Interface: operation '" ++ name ++ "'";
        const actual = functionInfo(Function, label);
        const expected = @typeInfo(@typeInfo(Signature).pointer.child).@"fn";

        if (actual.param_types.len != expected.param_types.len) {
            @compileError(label ++ ": provider parameter count does not match the contract");
        }

        const Erased = expected.param_types[0].?;
        const Receiver = actual.param_types[0].?;

        if (Receiver != *Provider and Receiver != *const Provider) {
            @compileError(label ++ ": provider receiver must point to its own type");
        }

        if (Erased == *const anyopaque and Receiver != *const Provider) {
            @compileError(label ++ ": a read-only operation requires a const provider receiver");
        }

        for (expected.param_types[1..], actual.param_types[1..]) |expected_param, actual_param| {
            if (expected_param.? != actual_param.?) {
                @compileError(label ++ ": provider parameter type does not match the contract");
            }
        }

        return actual;
    }

    fn Method(
        comptime Provider: type,
        comptime name: []const u8,
        comptime Signature: type,
        comptime operation: anytype,
    ) type {
        const method = methodInfo(Provider, name, Signature, operation);
        const signature = @typeInfo(@typeInfo(Signature).pointer.child).@"fn";
        const params = signature.param_types;

        const Erased = params[0].?;
        const Receiver = method.param_types[0].?;
        const Return = signature.return_type.?;

        const Adapter = struct {
            inline fn invoke(instance: Erased, args: anytype) Return {
                const receiver: Receiver = @ptrCast(@alignCast(instance));
                return @call(.auto, operation, .{receiver} ++ args);
            }
        };

        return switch (params.len) {
            1 => struct {
                fn call(instance: Erased) Return {
                    return Adapter.invoke(instance, .{});
                }
            },
            2 => struct {
                fn call(instance: Erased, first: params[1].?) Return {
                    return Adapter.invoke(instance, .{first});
                }
            },
            3 => struct {
                fn call(
                    instance: Erased,
                    first: params[1].?,
                    second: params[2].?,
                ) Return {
                    return Adapter.invoke(instance, .{ first, second });
                }
            },
            4 => struct {
                fn call(
                    instance: Erased,
                    first: params[1].?,
                    second: params[2].?,
                    third: params[3].?,
                ) Return {
                    return Adapter.invoke(instance, .{ first, second, third });
                }
            },
            else => unreachable,
        };
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "unit: optional operations and overrides retain independent dispatch" {
        const Provider = struct {
            value: u32 = 0,

            pub fn add(self: *@This(), amount: u32) void {
                self.value += amount;
            }

            pub fn reset(self: *@This()) void {
                self.value = 0;
            }
        };

        const Overrides = struct {
            fn multiply(self: *Provider, amount: u32) void {
                self.value *= amount;
            }

            fn read(self: *const Provider) u32 {
                return self.value;
            }
        };

        const Contract = struct {
            instance: *anyopaque,
            vtable: *const Vtable,

            pub const Vtable = struct {
                add: *const fn (*anyopaque, u32) void,
                reset: ?*const fn (*anyopaque) void = null,
                read: ?*const fn (*const anyopaque) u64 = null,
            };
        };

        var provider: Provider = .{ .value = 2 };
        const ordinary = Interface(Contract).bind(&provider);
        const overridden = Interface(Contract).bindWith(&provider, .{
            .add = &Overrides.multiply,
            .reset = null,
            .read = &Overrides.read,
        });

        ordinary.vtable.add(ordinary.instance, 3);
        overridden.vtable.add(overridden.instance, 4);
        try testing.expectEqual(@as(u64, 20), overridden.vtable.read.?(overridden.instance));
        try testing.expect(ordinary.vtable.read == null);
        try testing.expect(overridden.vtable.reset == null);

        ordinary.vtable.reset.?(ordinary.instance);
        try testing.expectEqual(@as(u64, 0), overridden.vtable.read.?(overridden.instance));
    }

    test "unit: overrides supply required operations for const providers" {
        const Provider = struct {
            value: u8,
        };

        const Overrides = struct {
            fn read(self: *const Provider) u8 {
                return self.value;
            }

            fn doubled(self: *const Provider) u16 {
                return @as(u16, self.value) * 2;
            }
        };

        const Contract = struct {
            instance: *const anyopaque,
            vtable: *const Vtable,

            pub const Vtable = struct {
                read: *const fn (*const anyopaque) u32,
                reset: ?*const fn (*const anyopaque) void,
            };
        };

        const provider: Provider = .{ .value = 7 };
        const first = Interface(Contract).bindWith(&provider, .{ .read = &Overrides.read });
        const second = Interface(Contract).bindWith(&provider, .{ .read = &Overrides.doubled });

        try testing.expectEqual(@as(u32, 7), first.vtable.read(first.instance));
        try testing.expectEqual(@as(u32, 14), second.vtable.read(second.instance));
        try testing.expect(first.vtable.reset == null);
    }

    test "unit: contract return types coerce values pointers optionals and errors" {
        const Provider = struct {
            value: u8 = 9,

            pub fn valuePtr(self: *@This()) *u8 {
                return &self.value;
            }

            pub fn optional(self: *const @This()) u8 {
                return self.value;
            }

            pub fn success(self: *const @This()) u8 {
                return self.value;
            }

            pub fn checked(self: *const @This(), fail: bool) error{Denied}!u32 {
                if (fail) return error.Denied;

                return self.value;
            }
        };

        const Contract = struct {
            instance: *anyopaque,
            vtable: *const Vtable,

            pub const Vtable = struct {
                valuePtr: *const fn (*anyopaque) *const u8,
                optional: *const fn (*const anyopaque) ?u32,
                success: *const fn (*const anyopaque) error{Denied}!u32,
                checked: *const fn (*const anyopaque, bool) error{ Denied, Unavailable }!u32,
            };
        };

        var provider: Provider = .{};
        const binding = Interface(Contract).bind(&provider);

        try testing.expectEqual(@as(u8, 9), binding.vtable.valuePtr(binding.instance).*);
        try testing.expectEqual(@as(?u32, 9), binding.vtable.optional(binding.instance));
        try testing.expectEqual(@as(u32, 9), try binding.vtable.success(binding.instance));
        try testing.expectEqual(@as(u32, 9), try binding.vtable.checked(binding.instance, false));
        try testing.expectError(error.Denied, binding.vtable.checked(binding.instance, true));

        provider.value = 17;
        try testing.expectEqual(@as(u8, 17), binding.vtable.valuePtr(binding.instance).*);
    }

    test "unit: mixed receivers preserve instance state and error progress" {
        const Account = struct {
            credits: u32,
            attempts: u32 = 0,

            const Error = error{InsufficientCredits};

            pub fn balance(self: *const @This()) u32 {
                return self.credits;
            }

            pub fn take(self: *@This(), amount: u32) Error!u32 {
                self.attempts += 1;

                if (amount > self.credits) {
                    return error.InsufficientCredits;
                }

                self.credits -= amount;
                return self.credits;
            }

            pub fn transfer(self: *@This(), destination: *@This(), amount: u32) Error!void {
                _ = try self.take(amount);
                destination.credits += amount;
            }

            pub fn adjust(self: *@This(), factor: u32, add: u32, subtract: u32) u32 {
                self.credits = self.credits * factor + add - subtract;
                return self.credits;
            }
        };

        const Contract = struct {
            instance: *anyopaque,
            vtable: *const Vtable,

            pub const Vtable = struct {
                balance: *const fn (*const anyopaque) u32,
                take: *const fn (*anyopaque, u32) Account.Error!u32,
                transfer: *const fn (*anyopaque, *Account, u32) Account.Error!void,
                adjust: *const fn (*anyopaque, u32, u32, u32) u32,
            };

            pub const bind = Interface(@This()).bind;
        };

        var source: Account = .{ .credits = 10 };
        var destination: Account = .{ .credits = 2 };
        const first = Contract.bind(&source);
        const second = Contract.bind(&destination);

        try first.vtable.transfer(first.instance, &destination, 3);
        try testing.expectEqual(@as(u32, 7), first.vtable.balance(first.instance));
        try testing.expectEqual(@as(u32, 5), second.vtable.balance(second.instance));

        try testing.expectError(error.InsufficientCredits, second.vtable.take(second.instance, 6));
        try testing.expectEqual(@as(u32, 3), try second.vtable.take(second.instance, 2));
        try testing.expectEqual(@as(u32, 2), destination.attempts);

        try testing.expectEqual(@as(u32, 24), first.vtable.adjust(first.instance, 3, 5, 2));
        try testing.expectEqual(@as(u32, 3), destination.credits);
    }

    test "unit: read-only contracts bind const and mutable providers of different types" {
        const Contract = struct {
            instance: *const anyopaque,
            vtable: *const Vtable,

            pub const Vtable = struct {
                value: *const fn (*const anyopaque) u32,
            };

            fn value(self: @This()) u32 {
                return self.vtable.value(self.instance);
            }
        };

        const Direct = struct {
            stored: u32,

            pub fn value(self: *const @This()) u32 {
                return self.stored;
            }
        };

        const Product = struct {
            left: u32,
            right: u32,

            pub fn value(self: *const @This()) u32 {
                return self.left * self.right;
            }
        };

        const direct: Direct = .{ .stored = 17 };
        var product: Product = .{ .left = 3, .right = 7 };

        const bindings = [_]Contract{
            Interface(Contract).bind(&direct),
            Interface(Contract).bind(&product),
        };

        try testing.expectEqual(@as(u32, 17), bindings[0].value());
        try testing.expectEqual(@as(u32, 21), bindings[1].value());

        product.right = 9;
        try testing.expectEqual(@as(u32, 27), bindings[1].value());
    }
};
