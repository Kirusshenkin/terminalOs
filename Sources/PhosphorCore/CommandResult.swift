/// Итог одной выполненной команды.
///
/// Живёт в ядре, а не в SSH-слое: это понятие «команда отработала», и оно
/// одинаково нужно докеру, рецептам и транспорту. Так DockerKit не обязан знать
/// про SSH вообще.
public struct CommandResult: Sendable, Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }
}
