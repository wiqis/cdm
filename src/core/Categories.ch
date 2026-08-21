// ChemicalDM — download categories.
//
// Downloads are classified into folders by file extension, mirroring XDM's
// category folders (Documents, Programs, Video, Music, Compressed, Other).
// The categorized path automatically places files under the download root.

public namespace cdm {

using std::string;
using std::string_view;
using std::Option;

    public enum Category {
        Other = 0,
        Documents = 1,
        Programs = 2,
        Video = 3,
        Music = 4,
        Compressed = 5
    }

    public const CATEGORY_OTHER_DIR : *char = ""
    public const CATEGORY_DOCS_DIR : *char = "Documents"
    public const CATEGORY_PROGRAMS_DIR : *char = "Programs"
    public const CATEGORY_VIDEO_DIR : *char = "Video"
    public const CATEGORY_MUSIC_DIR : *char = "Music"
    public const CATEGORY_COMPRESSED_DIR : *char = "Compressed"

    // Lower-case a std::string in place.
    func ascii_lower_inplace(s : &mut string) {
        for(var i = 0u; i < s.size(); i++) {
            var c = s.get(i)
            if(c >= 'A' && c <= 'Z') {
                s.set(i, (c + 32) as char)
            }
        }
    }

    func ascii_lower(v : string_view) : string {
        var out = string(v.data(), v.size())
        ascii_lower_inplace(&mut out)
        return out
    }

    // Map an individual file extension to a category. `ext` is lower-cased by
    // the caller and includes no leading dot.
    func category_for_extension_lower(ext : string_view) : Category {
        var h = fnv1_hash_view(&ext)
        switch(h) {
            comptime_fnv1_hash("pdf"), comptime_fnv1_hash("doc"),
            comptime_fnv1_hash("docx"), comptime_fnv1_hash("txt"),
            comptime_fnv1_hash("odt"), comptime_fnv1_hash("rtf"),
            comptime_fnv1_hash("xls"), comptime_fnv1_hash("xlsx"),
            comptime_fnv1_hash("ppt"), comptime_fnv1_hash("pptx"),
            comptime_fnv1_hash("md") => { return Category.Documents }
            comptime_fnv1_hash("exe"), comptime_fnv1_hash("msi"),
            comptime_fnv1_hash("deb"), comptime_fnv1_hash("rpm"),
            comptime_fnv1_hash("apk"), comptime_fnv1_hash("appimage") => { return Category.Programs }
            comptime_fnv1_hash("mp4"), comptime_fnv1_hash("mkv"),
            comptime_fnv1_hash("avi"), comptime_fnv1_hash("mov"),
            comptime_fnv1_hash("webm"), comptime_fnv1_hash("flv"),
            comptime_fnv1_hash("m4v"), comptime_fnv1_hash("mpg"),
            comptime_fnv1_hash("mpeg") => { return Category.Video }
            comptime_fnv1_hash("mp3"), comptime_fnv1_hash("aac"),
            comptime_fnv1_hash("wav"), comptime_fnv1_hash("flac"),
            comptime_fnv1_hash("ogg"), comptime_fnv1_hash("opus"),
            comptime_fnv1_hash("m4a"), comptime_fnv1_hash("wma") => { return Category.Music }
            comptime_fnv1_hash("zip"), comptime_fnv1_hash("rar"),
            comptime_fnv1_hash("7z"), comptime_fnv1_hash("tar"),
            comptime_fnv1_hash("gz"), comptime_fnv1_hash("bz2"),
            comptime_fnv1_hash("xz"), comptime_fnv1_hash("iso"),
            comptime_fnv1_hash("dmg"), comptime_fnv1_hash("jar") => { return Category.Compressed }
            default => { return Category.Other }
        }
    }

    // Map an individual file extension to a category.
    public func category_for_extension(ext : string_view) : Category {
        var lower = ascii_lower(ext)
        return category_for_extension_lower(string_view::make_view(&lower))
    }

    // Extract the extension of a filename (after the last dot, lower-cased).
    // Returns an empty string when there is none.
    func extension_of(name : string_view) : string {
        var out = string()
        var i = 0u
        var last_dot = std::NPOS
        while(i < name.size()) {
            if(name.get(i) == '.') { last_dot = i }
            i = i + 1u
        }
        if(last_dot == std::NPOS) { return out }
        var j = last_dot + 1u
        while(j < name.size()) {
            out.append(name.get(j))
            j = j + 1u
        }
        return ascii_lower(string_view::make_view(&out))
    }

    // Sub-directory name for a category.
    public func category_dir(c : Category) : string {
        if(c == Category.Documents) { return string::make_no_len(CATEGORY_DOCS_DIR) }
        if(c == Category.Programs) { return string::make_no_len(CATEGORY_PROGRAMS_DIR) }
        if(c == Category.Video) { return string::make_no_len(CATEGORY_VIDEO_DIR) }
        if(c == Category.Music) { return string::make_no_len(CATEGORY_MUSIC_DIR) }
        if(c == Category.Compressed) { return string::make_no_len(CATEGORY_COMPRESSED_DIR) }
        return string::make_no_len(CATEGORY_OTHER_DIR)
    }

    // Classify a suggested filename and return the categorized destination
    // directory (root + category sub-folder when the category is non-Other).
    public func categorize_path(root : string_view, filename : string_view) : string {
        var ext = extension_of(filename)
        var cat = category_for_extension_lower(string_view::make_view(&ext))
        var sub = category_dir(cat)
        var out = string(root.data(), root.size())
        if(sub.size() > 0) {
            out.append('/')
            out.append_string(&sub)
        }
        return out
    }

} // end namespace cdm