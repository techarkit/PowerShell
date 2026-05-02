$path = "C:\Your\Path"

$files = [System.Linq.Enumerable]::Count(
    [System.IO.Directory]::EnumerateFiles($path, "*", "AllDirectories")
)

$folders = [System.Linq.Enumerable]::Count(
    [System.IO.Directory]::EnumerateDirectories($path, "*", "AllDirectories")
)

"Files:   $files"
"Folders: $folders"
