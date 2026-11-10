import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let mine = list.filter { ($0["kCGWindowOwnerName"] as? String) == "Apps" && (($0["kCGWindowBounds"] as? [String: Any])?["Width"] as? Double ?? 0) > 800 }
print(mine.isEmpty ? "скрыто" : "видно")
