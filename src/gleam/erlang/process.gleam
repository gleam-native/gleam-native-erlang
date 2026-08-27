import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom.{type Atom}
import gleam/erlang/port.{type Port}
import gleam/erlang/reference.{type Reference}
import gleam/option
import gleam/string

// ---------------------------------------------------------------------------
// The native target's runtime primitives. On this target a `Pid` is a
// process id integer, a `Reference` (and a `Name`) is a unique integer
// tag, and every message is delivered under its subject's tag, with
// selective receive done by the runtime's mailbox. These functions do not
// exist on the BEAM, where the equivalents above are used instead.

/// A message whose type has been erased for storage in a selector; the
/// handler registered alongside it restores the type its subject
/// guaranteed.
type NativeMessage

@external(erlang, "gleam_erlang_ffi", "identity")
@external(native, "runtime", "gleam_native_identity")
fn coerce(value: a) -> b

@target(native)
@external(native, "runtime", "gleam_native_process_spawn")
fn native_spawn(body: fn() -> anything, link: Bool) -> Pid

@target(native)
@external(native, "runtime", "gleam_native_process_send_tagged")
fn native_send_tagged(pid: Pid, tag: Int, message: message) -> Bool

@target(native)
@external(native, "runtime", "gleam_native_process_receive_any")
fn native_receive_any(
  tags: List(Int),
  timeout_ms: Int,
  catch_all: Bool,
) -> Result(#(Int, NativeMessage), Nil)

@target(native)
@external(native, "runtime", "gleam_native_process_exit_tag")
fn native_exit_tag() -> Int

@target(native)
@external(native, "runtime", "gleam_native_process_monitor")
fn native_monitor(pid: Pid) -> Int

@target(native)
@external(native, "runtime", "gleam_native_process_demonitor")
fn native_demonitor(pid: Pid, tag: Int) -> Nil

@target(native)
@external(native, "runtime", "gleam_native_process_unlink")
fn native_unlink(pid: Pid) -> Nil

@target(native)
@external(native, "runtime", "gleam_native_process_exit_signal")
fn native_exit_signal(pid: Pid, reason: String) -> Nil

@target(native)
@external(native, "runtime", "gleam_native_process_kill")
fn native_kill(pid: Pid) -> Nil

@target(native)
@external(native, "runtime", "gleam_native_process_fresh_tag")
fn native_fresh_tag() -> Int

@target(native)
@external(native, "runtime", "gleam_native_process_register")
fn native_register(pid: Pid, name: Int) -> Bool

@target(native)
@external(native, "runtime", "gleam_native_process_unregister")
fn native_unregister(name: Int) -> Bool

@target(native)
@external(native, "runtime", "gleam_native_process_named")
fn native_named(name: Int) -> Int

@target(native)
@external(native, "runtime", "gleam_native_process_send_after_tagged")
fn native_send_after_tagged(
  pid: Pid,
  tag: Int,
  delay_ms: Int,
  message: message,
) -> Int

@target(native)
@external(native, "runtime", "gleam_native_process_cancel_timer")
fn native_cancel_timer(id: Int) -> Int

/// The tag a subject's messages are delivered under on the native target:
/// its reference for a plain subject, its name for a named one — both
/// unique integers there.
@target(native)
fn native_subject_tag(subject: Subject(message)) -> Int {
  case subject {
    Subject(_, tag) -> coerce(tag)
    NamedSubject(name) -> coerce(name)
  }
}

@target(native)
fn native_cast_exit_reason(reason: String) -> ExitReason {
  case reason {
    "normal" -> Normal
    "killed" -> Killed
    other -> Abnormal(dynamic.string(other))
  }
}

/// The reserved tag OTP-style system messages are delivered under on the
/// native target. Used by the `gleam_otp` package; not intended for
/// general use.
@internal
pub const system_message_tag = 2

/// Add a handler for a reserved raw native message tag. Used by the
/// `gleam_otp` package to receive system messages; not intended for
/// general use.
@target(native)
@internal
pub fn select_raw_tag(
  selector: Selector(payload),
  tag: Int,
  mapping: fn(message) -> payload,
) -> Selector(payload) {
  let assert NativeSelector(handlers, catch_all, tags) = selector
  let handler = fn(message: NativeMessage) { mapping(coerce(message)) }
  NativeSelector([#(tag, handler), ..handlers], catch_all, [tag, ..tags])
}

/// Send a message to the process with the given pid under a reserved raw
/// native tag. Used by the `gleam_otp` package to send system messages;
/// not intended for general use. Returns `False` if the process is not
/// alive.
@target(native)
@internal
pub fn send_raw_tagged(pid: Pid, tag: Int, message: anything) -> Bool {
  native_send_tagged(pid, tag, message)
}

/// A `Pid` (or Process identifier) is a reference to an Erlang process. Each
/// process has a `Pid` and it is one of the lowest level building blocks of
/// inter-process communication in the Erlang and Gleam OTP frameworks.
///
pub type Pid

/// Get the `Pid` for the current process.
///
@external(erlang, "erlang", "self")
@external(native, "runtime", "gleam_native_process_self")
pub fn self() -> Pid

/// Create a new Erlang process that runs concurrently to the creator. In other
/// languages this might be called a fibre, a green thread, or a coroutine.
///
/// The child process is linked to the creator process. When a process
/// terminates an exit signal is sent to all other processes that are linked to
/// it, causing the process to either terminate or have to handle the signal.
/// If you want an unlinked process use the `spawn_unlinked` function.
///
/// More can be read about processes and links in the [Erlang documentation][1].
///
/// [1]: https://www.erlang.org/doc/reference_manual/processes.html
///
/// This function starts processes via the Erlang `proc_lib` module, and as
/// such they benefit from the functionality described in the
/// [`proc_lib` documentation](https://www.erlang.org/doc/apps/stdlib/proc_lib.html).
///
@target(erlang)
@external(erlang, "proc_lib", "spawn_link")
pub fn spawn(running: fn() -> anything) -> Pid

@target(native)
pub fn spawn(running: fn() -> anything) -> Pid {
  native_spawn(running, True)
}

/// Create a new Erlang process that runs concurrently to the creator. In other
/// languages this might be called a fibre, a green thread, or a coroutine.
///
/// Typically you want to create a linked process using the `spawn` function,
/// but creating an unlinked process may be occasionally useful.
///
/// More can be read about processes and links in the [Erlang documentation][1].
///
/// [1]: https://www.erlang.org/doc/reference_manual/processes.html
///
/// This function starts processes via the Erlang `proc_lib` module, and as
/// such they benefit from the functionality described in the
/// [`proc_lib` documentation](https://www.erlang.org/doc/apps/stdlib/proc_lib.html).
///
@target(erlang)
@external(erlang, "proc_lib", "spawn")
pub fn spawn_unlinked(a: fn() -> anything) -> Pid

@target(native)
pub fn spawn_unlinked(a: fn() -> anything) -> Pid {
  native_spawn(a, False)
}

/// A `Subject` is a value that processes can use to send and receive messages
/// to and from each other in a well typed way.
///
/// Each subject is "owned" by the process that created it. Any process can use
/// the `send` function to send a message of the correct type to the process
/// that owns the subject, and the owner can use the `receive` function or the
/// `Selector` type to receive these messages.
///
/// The `Subject` type is similar to the "channel" types found in other
/// languages and the "topic" concept found in some pub-sub systems.
///
/// # Examples
///
/// ```gleam
/// let subject = new_subject()
///
/// // Send a message with the subject
/// send(subject, "Hello, Joe!")
///
/// // Receive the message
/// receive(subject, within: 10)
/// ```
///
pub opaque type Subject(message) {
  Subject(owner: Pid, tag: Dynamic)
  NamedSubject(name: Name(message))
}

/// Create a subject for the given process with the given tag. This is unsafe!
/// There's nothing here that verifies that the message the subject receives is
/// expected and that the tag is not already in use.
///
/// You should almost certainly not use this function.
///
@internal
pub fn unsafely_create_subject(owner: Pid, tag: Dynamic) -> Subject(message) {
  shared(Subject(owner, tag))
}

/// Subjects travel between processes constantly, so the native runtime
/// counts their boxes atomically: a send shares the same subject value
/// with the receiver instead of copying it. On the BEAM this is an
/// identity — subjects are ordinary tuples the VM copies like any term.
@external(native, "runtime", "gleam_native_make_shared")
fn shared(subject: Subject(message)) -> Subject(message) {
  subject
}

/// A name is an identity that a process can adopt, after which they will receive
/// messages sent to that name. This has two main advantages:
///
/// - Structuring OTP programs becomes easier as a name can be passed down the
///   program from the top level, while without names subjects and pids would
///   need to be passed up from the started process and then back down to the
///   code that works with that process.
/// - A new process can adopt the name of one that previously failed, allowing
///   it to transparently take-over and handle messages that are sent to that
///   name.
///
/// Names are globally unique as each process can have at most 1 name, and each
/// name can be registered by at most 1 process. Create all the names your
/// program needs at the start of your program and pass them down. Names are
/// Erlang atoms internally, so never create them dynamically. Generating too
/// many atoms will result in the atom table getting filled and causing the entire
/// virtual machine to crash.
///
/// The most commonly used name functions are `new_name`, `register`, and
/// `named_subject`.
///
pub type Name(message)

/// Generate a new name that a process can register itself with using the
/// `register` function, and other processes can send messages to using
/// `named_subject`.
///
/// The string argument is a prefix for the Erlang name. A unique suffix is
/// added to the prefix to make the name, removing the possibility of name
/// collisions.
///
/// ## Safe use
///
/// Use this function to create all the names your program needs when it
/// starts. **Never call this function dynamically** such as within a loop or
/// within a process within a supervision tree.
///
/// Each time this function is called a new atom will be generated. Generating
/// too many atoms will result in the atom table getting filled and causing the
/// entire virtual machine to crash.
///
@target(erlang)
@external(erlang, "gleam_erlang_ffi", "new_name")
pub fn new_name(prefix prefix: String) -> Name(message)

@target(native)
pub fn new_name(prefix prefix: String) -> Name(message) {
  // Native names are unique integers; there is no atom table to protect,
  // so the prefix is only for the programmer's benefit.
  let _ = prefix
  coerce(native_fresh_tag())
}

/// Create a subject for a name, which can be used to send and receive messages.
///
/// All subjects created for the same name behave identically and can be used
/// interchangably.
///
pub fn named_subject(name: Name(message)) -> Subject(message) {
  shared(NamedSubject(name))
}

/// Get the name of a subject, returning an error if it doesn't have one.
///
pub fn subject_name(subject: Subject(message)) -> Result(Name(message), Nil) {
  case subject {
    NamedSubject(name:) -> Ok(name)
    Subject(..) -> Error(Nil)
  }
}

/// Create a new `Subject` owned by the current process.
///
pub fn new_subject() -> Subject(message) {
  shared(Subject(owner: self(), tag: reference_to_dynamic(reference.new())))
}

/// Get the owner process for a subject, which is the process that will
/// receive any messages sent using the subject.
///
/// If the subject was created from a name and no process is currently
/// registered with that name then this function will return an error.
///
pub fn subject_owner(subject: Subject(message)) -> Result(Pid, Nil) {
  case subject {
    NamedSubject(name) -> named(name)
    Subject(pid, _) -> Ok(pid)
  }
}

type DoNotLeak

@target(erlang)
@external(erlang, "erlang", "send")
fn raw_send(a: Pid, b: message) -> DoNotLeak

@target(native)
fn raw_send(a: Pid, b: message) -> DoNotLeak {
  // The message is a `#(tag, payload)` tuple, exactly what the BEAM
  // sends; natively the tag is an integer the runtime delivers under.
  let #(tag, payload) = coerce(b)
  let _ = native_send_tagged(a, coerce(tag), payload)
  coerce(Nil)
}

/// Send a message to a process using a `Subject`. The message must be of the
/// type that the `Subject` accepts.
///
/// This function does not wait for the `Subject` owner process to call the
/// `receive` function, instead it returns once the message has been placed in
/// the process' mailbox.
///
/// # Panics
///
/// This function will panic when sending to a named subject if no process is
/// currently registed under that name.
///
/// # Ordering
///
/// If process P1 sends two messages to process P2 it is guaranteed that process
/// P1 will receive the messages in the order they were sent.
///
/// If you wish to receive the messages in a different order you can send them
/// on two different subjects and the receiver function can call the `receive`
/// function for each subject in the desired order, or you can write some Erlang
/// code to perform a selective receive.
///
/// # Examples
///
/// ```gleam
/// let subject = new_subject()
/// send(subject, "Hello, Joe!")
/// ```
///
@target(erlang)
pub fn send(subject: Subject(message), message: message) -> Nil {
  case subject {
    Subject(pid, tag) -> {
      raw_send(pid, #(tag, message))
    }
    NamedSubject(name) -> {
      let assert Ok(pid) = named(name) as "Sending to unregistered name"
      raw_send(pid, #(name, message))
    }
  }
  Nil
}

@target(native)
pub fn send(subject: Subject(message), message: message) -> Nil {
  let pid = case subject {
    Subject(pid, _) -> pid
    NamedSubject(name) -> {
      let assert Ok(pid) = named(name) as "Sending to unregistered name"
      pid
    }
  }
  // This straight-line statement is the function's only use of the
  // message, so the consuming send external takes ownership of it —
  // moving it into the receiver's mailbox when nothing else shares it.
  native_send_owned(pid, native_subject_tag(subject), message)
}

@target(native)
@external(native, "runtime", "gleam_native_process_send_owned")
fn native_send_owned(pid: Pid, tag: Int, message: message) -> Nil

/// Receive a message that has been sent to current process using the `Subject`.
///
/// If there is not an existing message for the `Subject` in the process'
/// mailbox or one does not arrive `within` the permitted timeout then the
/// `Error(Nil)` is returned.
///
/// Only the process that is owner of the `Subject` can receive a message using
/// it. If a process that does not own the `Subject` attempts to receive with it
/// then it will not receive a message.
///
/// To wait for messages from multiple `Subject`s at the same time see the
/// `Selector` type.
///
/// The `within` parameter specifies the timeout duration in milliseconds.
///
/// ## Panics
///
/// This function will panic if a process tries to receive with a non-named
/// subject that it does not own.
///
pub fn receive(
  from subject: Subject(message),
  within timeout: Int,
) -> Result(message, Nil) {
  case subject {
    NamedSubject(..) -> perform_receive(subject, timeout)
    Subject(owner:, ..) ->
      case owner == self() {
        True -> perform_receive(subject, timeout)
        False ->
          panic as "Cannot receive with a subject owned by another process"
      }
  }
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "receive")
fn perform_receive(
  subject: Subject(message),
  timeout: Int,
) -> Result(message, Nil)

@target(native)
fn perform_receive(
  subject: Subject(message),
  timeout: Int,
) -> Result(message, Nil) {
  case native_receive_any([native_subject_tag(subject)], timeout, False) {
    Ok(#(_, message)) -> Ok(coerce(message))
    Error(Nil) -> Error(Nil)
  }
}

/// Receive a message that has been sent to current process using the `Subject`.
///
/// Same as `receive` but waits forever and returns the message as is.
@target(erlang)
@external(erlang, "gleam_erlang_ffi", "receive")
pub fn receive_forever(from subject: Subject(message)) -> message

@target(native)
pub fn receive_forever(from subject: Subject(message)) -> message {
  let assert Ok(#(_, message)) =
    native_receive_any([native_subject_tag(subject)], -1, False)
  coerce(message)
}

/// A type that enables a process to wait for messages from multiple `Subject`s
/// at the same time, returning whichever message arrives first.
///
/// Used with the `new_selector`, `selector_receive`, and `select*` functions.
///
/// # Examples
///
/// ```gleam
/// let int_subject = new_subject()
/// let string_subject = new_subject()
/// send(int_subject, 1)
///
/// let selector =
///   new_selector()
///   |> select(string_subject)
///   |> select_map(int_subject, int.to_string)
///
/// selector_receive(selector, 10)
/// // -> Ok("1")
/// ```
///
pub opaque type Selector(payload) {
  /// On the BEAM: the selector structure built by `gleam_erlang_ffi`.
  ErlangSelector(raw: RawSelector(payload))
  /// On the native target: handlers keyed by the integer tag messages are
  /// delivered under, searched first-match, plus an optional catch-all.
  NativeSelector(
    handlers: List(#(Int, fn(NativeMessage) -> payload)),
    catch_all: option.Option(fn(NativeMessage) -> payload),
    /// The handlers' tags, precomputed so each receive passes them to the
    /// runtime without rebuilding the list.
    tags: List(Int),
  )
}

type RawSelector(payload)

@target(erlang)
fn raw_selector(selector: Selector(payload)) -> RawSelector(payload) {
  let assert ErlangSelector(raw) = selector
  raw
}

/// Create a new `Selector` which can be used to receive messages on multiple
/// `Subject`s at once.
///
@target(erlang)
pub fn new_selector() -> Selector(payload) {
  ErlangSelector(ffi_new_selector())
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "new_selector")
fn ffi_new_selector() -> RawSelector(payload)

@target(native)
pub fn new_selector() -> Selector(payload) {
  NativeSelector([], option.None, [])
}

/// Receive a message that has been sent to current process using any of the
/// `Subject`s that have been added to the `Selector` with the `select*`
/// functions.
///
/// If there is not an existing message for the `Selector` in the process'
/// mailbox or one does not arrive `within` the permitted timeout then the
/// `Error(Nil)` is returned.
///
/// Only the process that is owner of the `Subject`s can receive a message using
/// them. If a process that does not own the a `Subject` attempts to receive
/// with it then it will not receive a message.
///
/// To wait forever for the next message rather than for a limited amount of
/// time see the `selector_receive_forever` function.
///
/// The `within` parameter specifies the timeout duration in milliseconds.
///
@target(erlang)
pub fn selector_receive(
  from from: Selector(payload),
  within within: Int,
) -> Result(payload, Nil) {
  ffi_select_within(raw_selector(from), within)
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "select")
fn ffi_select_within(
  from: RawSelector(payload),
  within: Int,
) -> Result(payload, Nil)

@target(native)
pub fn selector_receive(
  from from: Selector(payload),
  within within: Int,
) -> Result(payload, Nil) {
  let assert NativeSelector(handlers, catch_all, tags) = from
  case native_receive_any(tags, within, catch_all != option.None) {
    Ok(#(tag, message)) -> Ok(apply_handler(handlers, catch_all, tag, message))
    Error(Nil) -> Error(Nil)
  }
}

@target(native)
fn apply_handler(
  handlers: List(#(Int, fn(NativeMessage) -> payload)),
  catch_all: option.Option(fn(NativeMessage) -> payload),
  tag: Int,
  message: NativeMessage,
) -> payload {
  case handlers {
    [#(candidate, handler), ..] if candidate == tag -> handler(message)
    [_, ..rest] -> apply_handler(rest, catch_all, tag, message)
    [] ->
      case catch_all {
        option.Some(handler) -> handler(message)
        option.None ->
          panic as "Selector received a message it has no handler for"
      }
  }
}

/// Similar to the `select` function but will wait forever for a message to
/// arrive rather than timing out after a specified amount of time.
///
@target(erlang)
pub fn selector_receive_forever(from from: Selector(payload)) -> payload {
  ffi_select_forever(raw_selector(from))
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "select")
fn ffi_select_forever(from: RawSelector(payload)) -> payload

@target(native)
pub fn selector_receive_forever(from from: Selector(payload)) -> payload {
  let assert NativeSelector(handlers, catch_all, tags) = from
  let assert Ok(#(tag, message)) =
    native_receive_any(tags, -1, catch_all != option.None)
  apply_handler(handlers, catch_all, tag, message)
}

/// Add a transformation function to a selector. When a message is received
/// using this selector the transformation function is applied to the message.
///
/// This function can be used to change the type of messages received and may
/// be useful when combined with the `merge_selector` function.
///
@target(erlang)
pub fn map_selector(a: Selector(a), b: fn(a) -> b) -> Selector(b) {
  ErlangSelector(ffi_map_selector(raw_selector(a), b))
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "map_selector")
fn ffi_map_selector(a: RawSelector(a), b: fn(a) -> b) -> RawSelector(b)

@target(native)
pub fn map_selector(a: Selector(a), b: fn(a) -> b) -> Selector(b) {
  let assert NativeSelector(handlers, catch_all, tags) = a
  NativeSelector(
    map_handlers(handlers, b),
    case catch_all {
      option.Some(handler) -> option.Some(fn(message) { b(handler(message)) })
      option.None -> option.None
    },
    tags,
  )
}

@target(native)
fn map_handlers(
  handlers: List(#(Int, fn(NativeMessage) -> a)),
  mapping: fn(a) -> b,
) -> List(#(Int, fn(NativeMessage) -> b)) {
  case handlers {
    [] -> []
    [#(tag, handler), ..rest] -> [
      #(tag, fn(message) { mapping(handler(message)) }),
      ..map_handlers(rest, mapping)
    ]
  }
}

/// Merge one selector into another, producing a selector that contains the
/// message handlers of both.
///
/// If a subject is handled by both selectors the handler function of the
/// second selector is used.
///
@target(erlang)
pub fn merge_selector(a: Selector(a), b: Selector(a)) -> Selector(a) {
  ErlangSelector(ffi_merge_selector(raw_selector(a), raw_selector(b)))
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "merge_selector")
fn ffi_merge_selector(a: RawSelector(a), b: RawSelector(a)) -> RawSelector(a)

@target(native)
pub fn merge_selector(a: Selector(a), b: Selector(a)) -> Selector(a) {
  let assert NativeSelector(first_handlers, first_catch_all, first_tags) = a
  let assert NativeSelector(second_handlers, second_catch_all, second_tags) = b
  // The second selector's handlers win for a subject both handle: they
  // are searched first.
  NativeSelector(
    append_handlers(second_handlers, first_handlers),
    case second_catch_all {
      option.Some(handler) -> option.Some(handler)
      option.None -> first_catch_all
    },
    append_tags(second_tags, first_tags),
  )
}

@target(native)
fn append_tags(first: List(Int), second: List(Int)) -> List(Int) {
  case first {
    [] -> second
    [tag, ..rest] -> [tag, ..append_tags(rest, second)]
  }
}

@target(native)
fn append_handlers(
  first: List(#(Int, fn(NativeMessage) -> payload)),
  second: List(#(Int, fn(NativeMessage) -> payload)),
) -> List(#(Int, fn(NativeMessage) -> payload)) {
  case first {
    [] -> second
    [handler, ..rest] -> [handler, ..append_handlers(rest, second)]
  }
}

pub type ExitMessage {
  ExitMessage(pid: Pid, reason: ExitReason)
}

pub type ExitReason {
  Normal
  Killed
  Abnormal(reason: Dynamic)
}

/// Add a handler for trapped exit messages. In order for these messages to be
/// sent to the process when a linked process exits the process must call the
/// `trap_exit` beforehand.
///
@target(erlang)
pub fn select_trapped_exits(
  selector: Selector(a),
  handler: fn(ExitMessage) -> a,
) -> Selector(a) {
  let tag = atom.create("EXIT")
  let handler = fn(message: #(Atom, Pid, Dynamic)) -> a {
    handler(ExitMessage(message.1, cast_exit_reason(message.2)))
  }
  insert_selector_handler(selector, #(tag, 3), handler)
}

@target(native)
pub fn select_trapped_exits(
  selector: Selector(a),
  handler: fn(ExitMessage) -> a,
) -> Selector(a) {
  let assert NativeSelector(handlers, catch_all, tags) = selector
  // A trapped exit arrives as a `#(pid, reason)` pair under the runtime's
  // reserved exit tag.
  let handler = fn(message: NativeMessage) -> a {
    let #(pid, reason) = coerce(message)
    handler(ExitMessage(pid, native_cast_exit_reason(reason)))
  }
  let tag = native_exit_tag()
  NativeSelector([#(tag, handler), ..handlers], catch_all, [tag, ..tags])
}

/// Discard all messages in the current process' mailbox.
///
/// Warning: This function may cause other processes to crash if they sent a
/// message to the current process and are waiting for a response, so use with
/// caution.
///
/// This function may be useful in tests.
///
@external(erlang, "gleam_erlang_ffi", "flush_messages")
@external(native, "runtime", "gleam_native_process_flush")
pub fn flush_messages() -> Nil

/// Add a new `Subject` to the `Selector` so that its messages can be selected
/// from the receiver process inbox.
///
/// See `select_map` to add subjects of a different message type.
///
/// See `deselect` to remove a subject from a selector.
///
pub fn select(
  selector: Selector(payload),
  for subject: Subject(payload),
) -> Selector(payload) {
  select_map(selector, subject, fn(x) { x })
}

/// Add a new `Subject` to the `Selector` so that its messages can be selected
/// from the receiver process inbox.
///
/// The `mapping` function provided with the `Subject` can be used to convert
/// the type of messages received using this `Subject`. This is useful for when
/// you wish to add multiple `Subject`s to a `Selector` when they have differing
/// message types. If you do not wish to transform the incoming messages in any
/// way then the `identity` function can be given.
///
/// See `deselect` to remove a subject from a selector.
///
@target(erlang)
pub fn select_map(
  selector: Selector(payload),
  for subject: Subject(message),
  mapping transform: fn(message) -> payload,
) -> Selector(payload) {
  let handler = fn(message: #(Reference, message)) { transform(message.1) }
  case subject {
    NamedSubject(name) -> insert_selector_handler(selector, #(name, 2), handler)
    Subject(_, tag:) -> insert_selector_handler(selector, #(tag, 2), handler)
  }
}

@target(native)
pub fn select_map(
  selector: Selector(payload),
  for subject: Subject(message),
  mapping transform: fn(message) -> payload,
) -> Selector(payload) {
  let assert NativeSelector(handlers, catch_all, tags) = selector
  let handler = fn(message: NativeMessage) { transform(coerce(message)) }
  let tag = native_subject_tag(subject)
  NativeSelector([#(tag, handler), ..handlers], catch_all, [tag, ..tags])
}

/// Remove a new `Subject` from the `Selector` so that its messages will not be
/// selected from the receiver process inbox.
///
@target(erlang)
pub fn deselect(
  selector: Selector(payload),
  for subject: Subject(message),
) -> Selector(payload) {
  case subject {
    NamedSubject(name) -> remove_selector_handler(selector, #(name, 2))
    Subject(_, tag:) -> remove_selector_handler(selector, #(tag, 2))
  }
}

@target(native)
pub fn deselect(
  selector: Selector(payload),
  for subject: Subject(message),
) -> Selector(payload) {
  let assert NativeSelector(handlers, catch_all, tags) = selector
  let tag = native_subject_tag(subject)
  NativeSelector(drop_handler(handlers, tag), catch_all, drop_tag(tags, tag))
}

@target(native)
fn drop_tag(tags: List(Int), tag: Int) -> List(Int) {
  case tags {
    [] -> []
    [candidate, ..rest] if candidate == tag -> drop_tag(rest, tag)
    [candidate, ..rest] -> [candidate, ..drop_tag(rest, tag)]
  }
}

@target(native)
fn drop_handler(
  handlers: List(#(Int, fn(NativeMessage) -> payload)),
  tag: Int,
) -> List(#(Int, fn(NativeMessage) -> payload)) {
  case handlers {
    [] -> []
    [#(candidate, _), ..rest] if candidate == tag -> drop_handler(rest, tag)
    [handler, ..rest] -> [handler, ..drop_handler(rest, tag)]
  }
}

/// Add a handler to a selector for tuple messages with a given tag in the
/// first position followed by a given number of fields.
///
/// Typically you want to use the `select` function with a `Subject` instead,
/// but this function may be useful if you need to receive messages sent from
/// other BEAM languages that do not use the `Subject` type.
///
/// This will not select messages sent via a subject even if the message has
/// the same tag in the first position. This is because when a message is sent
/// via a subject a new tag is used that is unique and specific to that subject.
///
@target(erlang)
pub fn select_record(
  selector: Selector(payload),
  tag tag: tag,
  fields arity: Int,
  mapping transform: fn(Dynamic) -> payload,
) -> Selector(payload) {
  insert_selector_handler(selector, #(tag, arity + 1), transform)
}

@target(native)
pub fn select_record(
  selector: Selector(payload),
  tag tag: tag,
  fields arity: Int,
  mapping transform: fn(Dynamic) -> payload,
) -> Selector(payload) {
  // Bare record messages come from other BEAM languages; on the native
  // target no such messages exist, so this handler can never match.
  let _ = tag
  let _ = arity
  let _ = transform
  selector
}

type AnythingSelectorTag {
  Anything
}

/// Add a catch-all handler to a selector that will be used when no other
/// handler in a selector is suitable for a given message.
///
/// This may be useful for when you want to ensure that any message in the inbox
/// is handled, or when you need to handle messages from other BEAM languages
/// which do not use subjects or record format messages.
///
@target(erlang)
pub fn select_other(
  selector: Selector(payload),
  mapping handler: fn(Dynamic) -> payload,
) -> Selector(payload) {
  insert_selector_handler(selector, Anything, handler)
}

@target(native)
pub fn select_other(
  selector: Selector(payload),
  mapping handler: fn(Dynamic) -> payload,
) -> Selector(payload) {
  let assert NativeSelector(handlers, _, tags) = selector
  NativeSelector(
    handlers,
    option.Some(fn(message) { handler(coerce(message)) }),
    tags,
  )
}

@target(erlang)
fn insert_selector_handler(
  a: Selector(payload),
  for for: tag,
  mapping mapping: fn(message) -> payload,
) -> Selector(payload) {
  ErlangSelector(ffi_insert_selector_handler(raw_selector(a), for, mapping))
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "insert_selector_handler")
fn ffi_insert_selector_handler(
  a: RawSelector(payload),
  for for: tag,
  mapping mapping: fn(message) -> payload,
) -> RawSelector(payload)

@target(erlang)
fn remove_selector_handler(
  a: Selector(payload),
  for for: tag,
) -> Selector(payload) {
  ErlangSelector(ffi_remove_selector_handler(raw_selector(a), for))
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "remove_selector_handler")
fn ffi_remove_selector_handler(
  a: RawSelector(payload),
  for for: tag,
) -> RawSelector(payload)

/// Suspends the process calling this function for the specified number of
/// milliseconds.
///
@external(erlang, "gleam_erlang_ffi", "sleep")
@external(native, "runtime", "gleam_native_process_sleep")
pub fn sleep(a: Int) -> Nil

/// Suspends the process forever! This may be useful for suspending the main
/// process in a Gleam program when it has no more work to do but we want other
/// processes to continue to work.
///
@external(erlang, "gleam_erlang_ffi", "sleep_forever")
@external(native, "runtime", "gleam_native_process_sleep_forever")
pub fn sleep_forever() -> Nil

/// Check to see whether the process for a given `Pid` is alive.
///
/// See the [Erlang documentation][1] for more information.
///
/// [1]: http://erlang.org/doc/man/erlang.html#is_process_alive-1
///
@external(erlang, "erlang", "is_process_alive")
@external(native, "runtime", "gleam_native_process_is_alive")
pub fn is_alive(a: Pid) -> Bool

type ProcessMonitorFlag {
  Process
}

@target(erlang)
@external(erlang, "erlang", "monitor")
fn erlang_monitor_process(a: ProcessMonitorFlag, b: Pid) -> Monitor

/// On the BEAM this is the reference `erlang:monitor/2` returned; on the
/// native target it is the monitored pid paired with the tag its down
/// message arrives under.
pub type Monitor

/// A message received when a monitored process or port exits.
///
pub type Down {
  ProcessDown(monitor: Monitor, pid: Pid, reason: ExitReason)
  PortDown(monitor: Monitor, port: Port, reason: ExitReason)
}

/// Start monitoring a process so that when the monitored process exits a
/// message is sent to the monitoring process.
///
/// The message is always sent exactly once. If the target process is
/// alive when this function is called, the message is sent when the target 
/// process exits. If the target process is not alive, the message will be
/// sent with reason `Abnormal(atom.to_dynamic(atom.create("noproc")))`.
/// In this case the message is NOT guaranteed to be delivered by the time
/// this function call returns.
///
/// The down message can be received with a selector and the
/// `select_monitors` function.
///
/// The process can be demonitored with the `demonitor_process` function.
///
@target(erlang)
pub fn monitor(pid: Pid) -> Monitor {
  erlang_monitor_process(Process, pid)
}

@target(native)
pub fn monitor(pid: Pid) -> Monitor {
  coerce(#(pid, native_monitor(pid)))
}

/// Select for a message sent for a given monitor.
///
/// Each monitor handler added to a selector has a select performance cost,
/// so prefer [`select_monitors`](#select_monitors) if you are select
/// for multiple monitors.
///
/// The handler can be removed from the selector later using
/// [`deselect_specific_monitor`](#deselect_specific_monitor).
///
@target(erlang)
pub fn select_specific_monitor(
  selector: Selector(payload),
  monitor: Monitor,
  mapping: fn(Down) -> payload,
) {
  insert_selector_handler(selector, monitor, mapping)
}

@target(native)
pub fn select_specific_monitor(
  selector: Selector(payload),
  monitor: Monitor,
  mapping: fn(Down) -> payload,
) {
  let assert NativeSelector(handlers, catch_all, tags) = selector
  let #(pid, tag): #(Pid, Int) = coerce(monitor)
  // The down message's payload is the exit reason as a string.
  let handler = fn(message: NativeMessage) {
    let reason: String = coerce(message)
    mapping(ProcessDown(
      monitor: monitor,
      pid: pid,
      reason: native_cast_exit_reason(reason),
    ))
  }
  NativeSelector([#(tag, handler), ..handlers], catch_all, [tag, ..tags])
}

/// Select for any messages sent for any monitors set up by the select process.
///
/// If you want to select for a specific message then use 
/// [`select_specific_monitor`](#select_specific_monitor), but this
/// function is preferred if you need to select for multiple monitors.
///
@target(erlang)
pub fn select_monitors(
  selector: Selector(payload),
  mapping: fn(Down) -> payload,
) -> Selector(payload) {
  insert_selector_handler(selector, #(atom.create("DOWN"), 5), fn(message) {
    mapping(cast_down_message(message))
  })
}

@target(native)
pub fn select_monitors(
  selector: Selector(payload),
  mapping: fn(Down) -> payload,
) -> Selector(payload) {
  let _ = selector
  let _ = mapping
  panic as "select_monitors is not yet supported on the native target; use select_specific_monitor"
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "cast_down_message")
fn cast_down_message(message: Dynamic) -> Down

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "cast_exit_reason")
fn cast_exit_reason(message: Dynamic) -> ExitReason

/// Remove the monitor for a process so that when the monitor process exits a
/// `Down` message is not sent to the monitoring process.
///
/// If the message has already been sent it is removed from the monitoring
/// process' mailbox.
///
@target(erlang)
pub fn demonitor_process(monitor monitor: Monitor) -> Nil {
  erlang_demonitor_process(monitor)
  Nil
}

@target(native)
pub fn demonitor_process(monitor monitor: Monitor) -> Nil {
  let #(pid, tag): #(Pid, Int) = coerce(monitor)
  native_demonitor(pid, tag)
}

@target(erlang)
@external(erlang, "gleam_erlang_ffi", "demonitor")
fn erlang_demonitor_process(monitor: Monitor) -> DoNotLeak

/// Remove a `Monitor` from a `Selector` prevoiusly added by
/// [`select_specific_monitor`](#select_specific_monitor). If
/// the `Monitor` is not in the `Selector` it will be returned
/// unchanged.
///
@target(erlang)
pub fn deselect_specific_monitor(
  selector: Selector(payload),
  monitor: Monitor,
) -> Selector(payload) {
  remove_selector_handler(selector, monitor)
}

@target(native)
pub fn deselect_specific_monitor(
  selector: Selector(payload),
  monitor: Monitor,
) -> Selector(payload) {
  let assert NativeSelector(handlers, catch_all, tags) = selector
  let #(_, tag): #(Pid, Int) = coerce(monitor)
  NativeSelector(drop_handler(handlers, tag), catch_all, drop_tag(tags, tag))
}

fn perform_call(
  subject: Subject(message),
  make_request: fn(Subject(reply)) -> message,
  run_selector: fn(Selector(reply)) -> Result(reply, Nil),
) -> reply {
  let reply_subject = new_subject()
  let assert Ok(callee) = subject_owner(subject)
    as "Callee subject had no owner"

  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let monitor = monitor(callee)

  // Send the request to the process over the channel
  send(subject, make_request(reply_subject))

  // Await a reply or handle failure modes (timeout, process down, etc)
  let reply =
    new_selector()
    |> select(reply_subject)
    |> select_specific_monitor(monitor, fn(down) {
      panic as { "callee exited: " <> string.inspect(down) }
    })
    |> run_selector

  let assert Ok(reply) = reply as "callee did not send reply before timeout"

  // Demonitor the process and close the channels as we're done
  demonitor_process(monitor)

  reply
}

// This function is based off of Erlang's gen:do_call/4.
/// Send a message to a process and wait a given number of milliseconds for a
/// reply.
///
/// ## Panics
///
/// This function will panic under the following circumstances:
/// - The callee process exited prior to sending a reply.
/// - The callee process did not send a reply within the permitted amount of
///   time.
/// - The subject is a named subject but no process is registered with that
///   name.
///
/// ## Examples
///
/// ```gleam
/// pub type Message {
///   // This message variant is to be used with `call`.
///   // The `reply` field contains a subject that the reply message will be
///   // sent over.
///   SayHello(reply_to: Subject(String), name: String)
/// }
/// 
/// // Typically we make public functions that hide the details of a process'
/// // message-based API.
/// pub fn say_hello(subject: Subject(Message), name: String) -> String {
///   // The `SayHello` message constructor is given _partially applied_ with
///   // all the arguments except the reply subject, which will be supplied by
///   // the `call` function itself before sending the message.
///   process.call(subject, 100, SayHello(_, name))
/// }
///
/// // This is the message handling logic used by the process that owns the
/// // subject, and so receives the messages. In a real project it would be
/// // within a process or some higher level abstraction like an actor, but for
/// // this demonstration that has been omitted.
/// pub fn handle_message(message: Message) -> Nil {
///   case message {
///     SayHello(reply:, name:) -> {
///       let data = "Hello, " <> name <> "!"
///       // The reply subject is used to send the response back.
///       // If the receiver process does not sent a reply in time then the
///       // caller will crash.
///       process.send(reply, data)
///     }
///   }
/// }
///
/// // Here is what it looks like using the functional API to call the process.
/// pub fn run(subject: Subject(Message)) {
///   say_hello(subject, "Lucy")
///   // -> "Hello, Lucy!"
///   say_hello(subject, "Nubi")
///   // -> "Hello, Nubi!"
/// }
/// ```
///
pub fn call(
  subject: Subject(message),
  waiting timeout: Int,
  sending make_request: fn(Subject(reply)) -> message,
) -> reply {
  perform_call(subject, make_request, selector_receive(_, timeout))
}

/// Send a message to a process and wait for a reply.
///
/// # Panics
///
/// This function will panic under the following circumstances:
/// - The callee process exited prior to sending a reply.
/// - The subject is a named subject but no process is registered with that
///   name.
///
pub fn call_forever(
  subject: Subject(message),
  make_request: fn(Subject(reply)) -> message,
) -> reply {
  perform_call(subject, make_request, fn(s) { Ok(selector_receive_forever(s)) })
}

/// Creates a link between the calling process and another process.
///
/// When a process crashes any linked processes will also crash. This is useful
/// to ensure that groups of processes that depend on each other all either
/// succeed or fail together.
///
/// Returns `True` if the link was created successfully, returns `False` if the
/// process was not alive and as such could not be linked.
///
@external(erlang, "gleam_erlang_ffi", "link")
@external(native, "runtime", "gleam_native_process_link")
pub fn link(pid pid: Pid) -> Bool

@target(erlang)
@external(erlang, "erlang", "unlink")
fn erlang_unlink(pid pid: Pid) -> Bool

@target(native)
fn erlang_unlink(pid pid: Pid) -> Bool {
  native_unlink(pid)
  True
}

/// Removes any existing link between the caller process and the target process.
///
pub fn unlink(pid: Pid) -> Nil {
  erlang_unlink(pid)
  Nil
}

pub opaque type Timer {
  /// On the BEAM: the timer reference `erlang:send_after/3` returned.
  ErlangTimer(raw: RawTimer)
  /// On the native target: the runtime's timer id.
  NativeTimer(id: Int)
}

type RawTimer

@target(erlang)
@external(erlang, "erlang", "send_after")
fn pid_send_after(a: Int, b: Pid, c: #(Dynamic, msg)) -> RawTimer

@target(erlang)
@external(erlang, "erlang", "send_after")
fn name_send_after(a: Int, b: Name(msg), c: #(Name(msg), msg)) -> RawTimer

/// Schedule a message to be sent after the specified number of milliseconds.
///
/// The process is free to perform other work in the mean time.
///
/// To cancel the sending of a scheduled message call the `cancel_timer`
/// function on the timer value returned by this function.
///
/// If you would like to learn more about timers see the
/// [Erlang runtime documentation](https://www.erlang.org/doc/apps/erts/time_correction.html#timers).
///
@target(erlang)
pub fn send_after(subject: Subject(msg), delay: Int, message: msg) -> Timer {
  case subject {
    NamedSubject(name) ->
      ErlangTimer(name_send_after(delay, name, #(name, message)))
    Subject(owner, tag) ->
      ErlangTimer(pid_send_after(delay, owner, #(tag, message)))
  }
}

@target(native)
pub fn send_after(subject: Subject(msg), delay: Int, message: msg) -> Timer {
  case subject {
    NamedSubject(name) -> {
      // The name is resolved when the timer fires, so a re-registered
      // process receives the message.
      let tag: Int = coerce(name)
      NativeTimer(native_send_after_named(tag, delay, message))
    }
    Subject(owner, tag) ->
      NativeTimer(native_send_after_tagged(owner, coerce(tag), delay, message))
  }
}

@target(native)
@external(native, "runtime", "gleam_native_process_send_after_named")
fn native_send_after_named(name: Int, delay_ms: Int, message: msg) -> Int

@external(erlang, "gleam_erlang_ffi", "identity")
@external(native, "runtime", "gleam_native_identity")
fn reference_to_dynamic(reference: Reference) -> Dynamic

@target(erlang)
@external(erlang, "erlang", "cancel_timer")
fn erlang_cancel_timer(a: RawTimer) -> Dynamic

/// Values returned when a timer is cancelled.
///
pub type Cancelled {
  /// The timer could not be found. It likely has already triggered.
  ///
  TimerNotFound

  /// The timer was found and cancelled before it triggered.
  ///
  /// The amount of remaining time before the timer was due to be triggered is
  /// returned in milliseconds.
  ///
  Cancelled(time_remaining: Int)
}

/// Cancel a given timer, causing it not to trigger if it has not done already.
///
@target(erlang)
pub fn cancel_timer(timer: Timer) -> Cancelled {
  let assert ErlangTimer(raw) = timer
  case decode.run(erlang_cancel_timer(raw), decode.int) {
    Ok(i) -> Cancelled(i)
    Error(_) -> TimerNotFound
  }
}

@target(native)
pub fn cancel_timer(timer: Timer) -> Cancelled {
  let assert NativeTimer(id) = timer
  case native_cancel_timer(id) {
    remaining if remaining >= 0 -> Cancelled(remaining)
    _ -> TimerNotFound
  }
}

type KillFlag {
  Kill
}

@target(erlang)
@external(erlang, "erlang", "exit")
fn erlang_kill(to to: Pid, because because: KillFlag) -> Bool

@target(native)
fn erlang_kill(to to: Pid, because because: KillFlag) -> Bool {
  let _ = because
  native_kill(to)
  True
}

// Go, my pretties. Kill! Kill!
// - Bart Simpson
//
/// Send an untrappable `kill` exit signal to the target process.
///
/// See the documentation for the Erlang [`erlang:exit`][1] function for more
/// information.
///
/// [1]: https://erlang.org/doc/man/erlang.html#exit-1
///
pub fn kill(pid: Pid) -> Nil {
  erlang_kill(pid, Kill)
  Nil
}

@target(erlang)
@external(erlang, "erlang", "exit")
fn erlang_send_exit(to to: Pid, because because: whatever) -> Bool

@target(native)
fn erlang_send_exit(to to: Pid, because because: whatever) -> Bool {
  // Native exit reasons are strings; other values are inspected into one.
  let reason = case decode.run(coerce(because), decode.string) {
    Ok(text) -> text
    Error(_) -> string.inspect(because)
  }
  native_exit_signal(to, reason)
  True
}

// TODO: test
/// Sends an exit signal to a process, indicating that the process is to shut
/// down.
///
/// See the [Erlang documentation][1] for more information.
///
/// [1]: http://erlang.org/doc/man/erlang.html#exit-2
///
@target(erlang)
pub fn send_exit(to pid: Pid) -> Nil {
  erlang_send_exit(pid, Normal)
  Nil
}

@target(native)
pub fn send_exit(to pid: Pid) -> Nil {
  native_exit_signal(pid, "normal")
}

/// Sends an exit signal to a process, indicating that the process is to shut
/// down due to an abnormal reason such as a failure.
///
/// See the [Erlang documentation][1] for more information.
///
/// [1]: http://erlang.org/doc/man/erlang.html#exit-2
///
pub fn send_abnormal_exit(pid: Pid, reason: anything) -> Nil {
  erlang_send_exit(pid, reason)
  Nil
}

/// Set whether the current process is to trap exit signals or not.
///
/// When not trapping exits if a linked process crashes the exit signal
/// propagates to the process which will also crash.
/// This is the normal behaviour before this function is called.
///
/// When trapping exits (after this function is called) if a linked process
/// crashes an exit message is sent to the process instead. These messages can
/// be handled with the `select_trapped_exits` function.
///
@external(erlang, "gleam_erlang_ffi", "trap_exits")
@external(native, "runtime", "gleam_native_process_trap_exits")
pub fn trap_exits(a: Bool) -> Nil

/// Register a process under a given name, allowing it to be looked up using
/// the `named` function.
///
/// This function will return an error under the following conditions:
/// - The process for the pid no longer exists.
/// - The name has already been registered.
/// - The process already has a name.
///
@target(erlang)
@external(erlang, "gleam_erlang_ffi", "register_process")
pub fn register(pid: Pid, name: Name(message)) -> Result(Nil, Nil)

@target(native)
pub fn register(pid: Pid, name: Name(message)) -> Result(Nil, Nil) {
  case native_register(pid, coerce(name)) {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}

/// Un-register a process name, after which the process can no longer be looked
/// up by that name, and both the name and the process can be re-used in other
/// registrations.
///
/// It is possible to un-register process that are not from your application,
/// including those from Erlang/OTP itself. This is not recommended and will
/// likely result in undesirable behaviour and crashes.
///
@target(erlang)
@external(erlang, "gleam_erlang_ffi", "unregister_process")
pub fn unregister(name: Name(message)) -> Result(Nil, Nil)

@target(native)
pub fn unregister(name: Name(message)) -> Result(Nil, Nil) {
  case native_unregister(coerce(name)) {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}

/// Look up a process by registered name, returning the pid if it exists.
///
@target(erlang)
@external(erlang, "gleam_erlang_ffi", "process_named")
pub fn named(name: Name(a)) -> Result(Pid, Nil)

@target(native)
pub fn named(name: Name(a)) -> Result(Pid, Nil) {
  case native_named(coerce(name)) {
    0 -> Error(Nil)
    pid -> Ok(coerce(pid))
  }
}
