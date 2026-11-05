// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Darwin

// MARK: - Secure terminal input (tanpa echo ke layar)

func readSecret(prompt: String) -> String? {
    FileHandle.standardOutput.write("\(prompt): ".data(using: .utf8)!)

    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)
    var newTermios = oldTermios
    newTermios.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

    let line = readLine()

    tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
    print()
    return line
}
