$path = "D:\"

$files = 0
$folders = 0

$stack = [System.Collections.Generic.Stack[string]]::new()
$stack.Push((Resolve-Path $path).ProviderPath)

while ($stack.Count -gt 0) {
    $dir = $stack.Pop()

    try {
        foreach ($file in [System.IO.Directory]::EnumerateFiles($dir)) {
            $files++
        }

        foreach ($subdir in [System.IO.Directory]::EnumerateDirectories($dir)) {
            $folders++

            try {
                $attrs = [System.IO.File]::GetAttributes($subdir)

                if (($attrs -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                    $stack.Push($subdir)
                }
            } catch {}
        }
    }
    catch [System.UnauthorizedAccessException] {}
    catch [System.IO.IOException] {}
}

"Files:   $files"
"Folders: $folders"
