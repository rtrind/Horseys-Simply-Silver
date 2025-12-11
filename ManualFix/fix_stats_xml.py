#!/usr/bin/env python3
"""
Stats.xml Cleanup Tool for OutFox/StepMania

Merges duplicate Steps entries (caused by empty MD5Hash bug), ensures consistent
hashes, and properly orders difficulties and scores.

This script surgically modifies only the <SongScores> section, preserving all
other formatting and content exactly as-is.

Hash Resolution Strategy:
1. Build a hash cache from ALL Stats.xml files (Machine + all LocalProfiles)
2. Use cached hashes when fixing empty hash entries
3. If multiple different hashes exist for same song/steps, report conflict
4. If no hash found, keep empty (will be populated when song is played)

Usage:
    python fix_stats_xml.py --stats "path/to/Stats.xml" --save-dir "path/to/Save"
    python fix_stats_xml.py --stats "path/to/Stats.xml" --save-dir "path/to/Save" --dry-run
"""

# Suppress deprecation warnings BEFORE any other imports
import warnings
warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=DeprecationWarning)

import argparse
import json
import re
import shutil
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
import xml.etree.ElementTree as ET


# Difficulty ordering (lower = earlier in file)
DIFFICULTY_ORDER = {
    'Beginner': 0,
    'Easy': 1,
    'Medium': 2,
    'Hard': 3,
    'Challenge': 4,
    'Edit': 5,
}

# Grade ordering (lower Tier number = better grade)
def grade_to_int(grade: str) -> int:
    """Convert grade string to comparable integer. Lower is better."""
    if not grade:
        return 999
    if grade == 'Failed':
        return 100
    match = re.match(r'Tier(\d+)', grade)
    if match:
        return int(match.group(1))
    return 999


def parse_datetime(dt_str: str) -> datetime:
    """Parse datetime string from Stats.xml."""
    try:
        return datetime.strptime(dt_str.strip(), '%Y-%m-%d %H:%M:%S')
    except ValueError:
        try:
            return datetime.strptime(dt_str.strip(), '%Y-%m-%d')
        except ValueError:
            return datetime.min


class HashCache:
    """Cache of MD5 hashes collected from all Stats.xml files."""
    
    def __init__(self):
        # Key: (song_dir, steps_type, difficulty) -> Set of hashes found
        self.hashes: Dict[Tuple[str, str, str], Set[str]] = defaultdict(set)
        self.conflicts: List[Tuple[str, str, str, Set[str]]] = []  # Entries with multiple hashes
    
    def add_hash(self, song_dir: str, steps_type: str, difficulty: str, md5_hash: str):
        """Add a hash to the cache."""
        if md5_hash and md5_hash.strip():
            key = (song_dir, steps_type, difficulty)
            self.hashes[key].add(md5_hash)
    
    def get_hash(self, song_dir: str, steps_type: str, difficulty: str) -> Optional[str]:
        """Get hash from cache. Returns None if not found or if there's a conflict."""
        key = (song_dir, steps_type, difficulty)
        hashes = self.hashes.get(key, set())
        
        if len(hashes) == 1:
            return next(iter(hashes))
        elif len(hashes) > 1:
            # Multiple hashes found - this is a conflict
            return None
        return None
    
    def find_conflicts(self) -> List[Tuple[str, str, str, Set[str]]]:
        """Find all entries with multiple different hashes."""
        conflicts = []
        for key, hashes in self.hashes.items():
            if len(hashes) > 1:
                conflicts.append((key[0], key[1], key[2], hashes))
        return conflicts
    
    def save_to_file(self, path: Path):
        """Save cache to JSON file for manual editing."""
        data = {}
        for (song_dir, steps_type, difficulty), hashes in self.hashes.items():
            key = f"{song_dir}|{steps_type}|{difficulty}"
            data[key] = list(hashes)
        
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, sort_keys=True)
    
    def load_from_file(self, path: Path):
        """Load cache from JSON file (for manual overrides)."""
        if not path.exists():
            return
        
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        for key, hashes in data.items():
            parts = key.split('|')
            if len(parts) == 3:
                song_dir, steps_type, difficulty = parts
                for h in hashes:
                    self.add_hash(song_dir, steps_type, difficulty, h)


def extract_song_scores_section_for_cache(xml_content: str) -> Optional[str]:
    """Extract SongScores section for hash cache building."""
    start_match = re.search(r'<SongScores\s*>', xml_content)
    if not start_match:
        return None
    
    end_match = re.search(r'</SongScores\s*>', xml_content)
    if not end_match:
        return None
    
    return xml_content[start_match.start():end_match.end()]


def load_hash_cache_from_songdb(save_dir: Path) -> HashCache:
    """Load hash cache from song.db cache file (extracted by extract_hashes_from_songdb.py)."""
    cache = HashCache()
    
    # First try the pre-extracted JSON cache
    songdb_cache = save_dir / "songdb_hash_cache.json"
    if songdb_cache.exists():
        print(f"Loading hash cache from song.db extract: {songdb_cache}")
        with open(songdb_cache, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        for key, md5_hash in data.items():
            parts = key.split('|')
            if len(parts) == 3:
                song_dir, steps_type, difficulty = parts
                cache.add_hash(song_dir, steps_type, difficulty, md5_hash)
        
        print(f"  Loaded {len(cache.hashes)} chart hashes\n")
        return cache
    
    # If no pre-extracted cache, try to extract directly from song.db
    songdb_path = save_dir.parent / "Cache" / "song.db"
    if songdb_path.exists():
        print(f"Extracting hashes from song.db: {songdb_path}")
        try:
            import sqlite3
            import lz4.block
            
            conn = sqlite3.connect(songdb_path)
            cursor = conn.cursor()
            cursor.execute("SELECT FULLSIZE, DATA FROM SONGS")
            rows = cursor.fetchall()
            
            for fullsize, data in rows:
                try:
                    decompressed = lz4.block.decompress(data, uncompressed_size=fullsize)
                    text = decompressed.decode('utf-8', errors='replace')
                    
                    song_dir_match = re.search(r'#SONGDIR:([^;]+);', text)
                    if not song_dir_match:
                        continue
                    song_dir = song_dir_match.group(1)
                    
                    sections = text.split('#NOTEDATA:;')
                    for section in sections[1:]:
                        hash_match = re.search(r'#CHARTHASH:([a-f0-9]{32});', section, re.IGNORECASE)
                        steps_type_match = re.search(r'#STEPSTYPE:([^;]+);', section)
                        difficulty_match = re.search(r'#DIFFICULTY:([^;]+);', section)
                        
                        if hash_match and steps_type_match and difficulty_match:
                            md5_hash = hash_match.group(1).lower()
                            steps_type = steps_type_match.group(1)
                            difficulty = difficulty_match.group(1)
                            steps_type_xml = "StepsType_" + "_".join(
                                word.capitalize() for word in steps_type.split('-')
                            )
                            cache.add_hash(song_dir, steps_type_xml, difficulty, md5_hash)
                except:
                    pass
            
            conn.close()
            print(f"  Extracted {len(cache.hashes)} chart hashes\n")
            return cache
            
        except ImportError:
            print("  WARNING: lz4 module not installed, cannot extract from song.db")
        except Exception as e:
            print(f"  WARNING: Error reading song.db: {e}")
    
    print("  No song.db cache found")
    return cache


def build_hash_cache(save_dir: Path, cache_file: Optional[Path] = None, 
                     use_existing_cache: bool = False) -> HashCache:
    """Build hash cache, preferring song.db over Stats.xml files.
    
    Args:
        save_dir: Path to Save directory
        cache_file: Path to cache JSON file (legacy, not used with song.db)
        use_existing_cache: If True and cache_file exists, skip rebuilding
    """
    # First try to load from song.db cache (most complete source)
    cache = load_hash_cache_from_songdb(save_dir)
    if len(cache.hashes) > 0:
        return cache
    
    # Fall back to Stats.xml files if song.db not available
    print("Falling back to Stats.xml hash extraction...")
    cache = HashCache()
    
    # If using existing cache and file exists, just load it
    if use_existing_cache and cache_file and cache_file.exists():
        print(f"Loading existing hash cache from: {cache_file}")
        cache.load_from_file(cache_file)
        total_entries = len(cache.hashes)
        unique_hashes = sum(1 for h in cache.hashes.values() if len(h) == 1)
        conflicts = sum(1 for h in cache.hashes.values() if len(h) > 1)
        print(f"  Loaded {total_entries} entries ({unique_hashes} unique, {conflicts} conflicts)\n")
        return cache
    
    # Find all Stats.xml files from LocalProfiles only (not MachineProfile)
    stats_files = []
    
    local_profiles = save_dir / "LocalProfiles"
    if local_profiles.exists():
        for profile_dir in sorted(local_profiles.iterdir()):
            if profile_dir.is_dir():
                profile_stats = profile_dir / "Stats.xml"
                if profile_stats.exists():
                    stats_files.append(profile_stats)
    
    if not stats_files:
        print("WARNING: No Stats.xml files found in LocalProfiles!")
        return cache
    
    print(f"Building hash cache from {len(stats_files)} profile Stats.xml files...")
    for sf in stats_files:
        print(f"  - {sf}")
    print()
    
    total_hashes_found = 0
    
    for stats_file in stats_files:
        hashes_in_file = 0
        try:
            with open(stats_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            song_scores = extract_song_scores_section_for_cache(content)
            if not song_scores:
                print(f"  {stats_file.name}: No SongScores section found")
                continue
            
            # Parse and extract hashes
            try:
                root = ET.fromstring(song_scores)
                for song in root.findall('Song'):
                    song_dir = song.get('Dir', '')
                    for steps in song.findall('Steps'):
                        steps_type = steps.get('StepsType', '')
                        difficulty = steps.get('Difficulty', '')
                        md5_hash = steps.get('MD5Hash', '')
                        
                        if md5_hash and md5_hash.strip():
                            cache.add_hash(song_dir, steps_type, difficulty, md5_hash)
                            hashes_in_file += 1
                
                print(f"  {stats_file.parent.name}: {hashes_in_file} hashes found")
                total_hashes_found += hashes_in_file
                
            except ET.ParseError as e:
                print(f"  {stats_file.name}: Parse error - {e}")
                continue
                
        except Exception as e:
            print(f"  {stats_file.name}: Error - {e}")
    
    print(f"\nTotal hashes collected: {total_hashes_found}")
    
    # Report stats
    total_entries = len(cache.hashes)
    unique_hashes = sum(1 for h in cache.hashes.values() if len(h) == 1)
    conflicts = cache.find_conflicts()
    
    print(f"Unique chart entries: {total_entries}")
    print(f"  - Single hash (usable): {unique_hashes}")
    print(f"  - Multiple hashes (conflicts): {len(conflicts)}")
    
    if conflicts:
        print(f"\nConflicts (need manual resolution):")
        for song_dir, steps_type, difficulty, hashes in conflicts:
            print(f"  {song_dir}")
            print(f"    [{difficulty}] {steps_type}: {sorted(hashes)}")
    
    # Always save cache if cache_file specified
    if cache_file:
        cache.save_to_file(cache_file)
        print(f"\nHash cache saved to: {cache_file}")
    
    print()
    return cache


class StepsEntry:
    """Represents a Steps entry with its high scores."""
    
    def __init__(self, element: ET.Element):
        self.element = element
        self.chart_type = element.get('ChartType', '')
        self.difficulty = element.get('Difficulty', '')
        # Handle both old format (OnlineHash) and new format (MD5Hash)
        self.md5_hash = element.get('MD5Hash', '')
        self.steps_type = element.get('StepsType', '')
        # Track if this uses old format (for normalization)
        self.uses_old_format = 'OnlineHash' in element.attrib or 'OnlineDescription' in element.attrib
        
        # Parse HighScoreList
        hsl = element.find('HighScoreList')
        self.num_times_played = 0
        self.last_played = ''
        self.high_grade = ''
        self.high_scores: List[ET.Element] = []
        
        if hsl is not None:
            ntp = hsl.find('NumTimesPlayed')
            if ntp is not None and ntp.text:
                self.num_times_played = int(ntp.text)
            
            lp = hsl.find('LastPlayed')
            if lp is not None and lp.text:
                self.last_played = lp.text
            
            hg = hsl.find('HighGrade')
            if hg is not None and hg.text:
                self.high_grade = hg.text
            
            self.high_scores = hsl.findall('HighScore')
    
    def get_key(self) -> Tuple[str, str]:
        """Return key for grouping: (StepsType, Difficulty)"""
        return (self.steps_type, self.difficulty)


class SongEntry:
    """Represents a Song entry with all its Steps."""
    
    def __init__(self, element: ET.Element):
        self.element = element
        self.dir = element.get('Dir', '')
        self.steps: List[StepsEntry] = []
        
        for steps_elem in element.findall('Steps'):
            self.steps.append(StepsEntry(steps_elem))


def merge_steps_entries(entries: List[StepsEntry], resolved_hash: str) -> ET.Element:
    """Merge multiple Steps entries into one."""
    
    # Aggregate metadata
    total_times_played = sum(e.num_times_played for e in entries)
    
    # Find latest play date
    last_played_dates = [parse_datetime(e.last_played) for e in entries if e.last_played]
    last_played = max(last_played_dates).strftime('%Y-%m-%d') if last_played_dates else ''
    
    # Find best grade (lowest tier number)
    grades = [e.high_grade for e in entries if e.high_grade]
    best_grade = min(grades, key=grade_to_int) if grades else ''
    
    # Collect all high scores
    all_scores: List[Tuple[float, datetime, ET.Element]] = []
    for entry in entries:
        for hs in entry.high_scores:
            percent_dp = 0.0
            dt = datetime.min
            
            pdp = hs.find('PercentDP')
            if pdp is not None and pdp.text:
                percent_dp = float(pdp.text)
            
            dt_elem = hs.find('DateTime')
            if dt_elem is not None and dt_elem.text:
                dt = parse_datetime(dt_elem.text)
            
            all_scores.append((percent_dp, dt, hs))
    
    # Sort: PercentDP descending, DateTime ascending for ties
    all_scores.sort(key=lambda x: (-x[0], x[1]))
    
    # Build new Steps element
    first = entries[0]
    new_steps = ET.Element('Steps')
    new_steps.set('ChartType', first.chart_type)
    new_steps.set('Difficulty', first.difficulty)
    new_steps.set('MD5Hash', resolved_hash)
    new_steps.set('StepsType', first.steps_type)
    
    # Build HighScoreList
    hsl = ET.SubElement(new_steps, 'HighScoreList')
    
    ntp = ET.SubElement(hsl, 'NumTimesPlayed')
    ntp.text = str(total_times_played)
    
    if last_played:
        lp = ET.SubElement(hsl, 'LastPlayed')
        lp.text = last_played
    
    if best_grade:
        hg = ET.SubElement(hsl, 'HighGrade')
        hg.text = best_grade
    
    # Add all high scores
    for _, _, hs in all_scores:
        hsl.append(hs)
    
    return new_steps


def resolve_hash(entries: List[StepsEntry], song_dir: str, steps_type: str, 
                 difficulty: str, hash_cache: HashCache) -> Tuple[str, bool]:
    """Resolve the MD5 hash for a group of Steps entries.
    
    Returns: (hash, was_found) - hash may be empty string if not found
    """
    
    # First check entries themselves for valid hashes
    valid_hashes = set(e.md5_hash for e in entries if e.md5_hash and e.md5_hash.strip())
    
    if len(valid_hashes) == 1:
        # Single valid hash in entries - use it
        return next(iter(valid_hashes)), True
    
    # Try hash cache (try both with and without leading slash)
    cached_hash = hash_cache.get_hash(song_dir, steps_type, difficulty)
    if not cached_hash and not song_dir.startswith('/'):
        cached_hash = hash_cache.get_hash('/' + song_dir, steps_type, difficulty)
    if cached_hash:
        return cached_hash, True
    
    # If we have multiple valid hashes in entries, that's a conflict
    if len(valid_hashes) > 1:
        print(f"    WARNING: Multiple hashes in entries: {valid_hashes}")
        return '', False
    
    # No hash found anywhere - leave empty
    return '', False


def process_song(song: SongEntry, hash_cache: HashCache, dry_run: bool) -> Tuple[ET.Element, int, int, List[Tuple[str, str]]]:
    """Process a single song, merging duplicate Steps entries.
    
    Returns: (new_song_element, num_duplicates_merged, num_scores_consolidated, missing_hashes_list)
    missing_hashes_list is a list of (difficulty, steps_type) tuples for charts with no hash found
    """
    
    # Group Steps by (StepsType, Difficulty)
    steps_groups: Dict[Tuple[str, str], List[StepsEntry]] = {}
    for steps in song.steps:
        key = steps.get_key()
        if key not in steps_groups:
            steps_groups[key] = []
        steps_groups[key].append(steps)
    
    # Count duplicates
    duplicates_merged = sum(1 for entries in steps_groups.values() if len(entries) > 1)
    scores_consolidated = 0
    missing_hashes: List[Tuple[str, str]] = []  # (difficulty, steps_type)
    
    # Build new song element (keep original path format)
    new_song = ET.Element('Song')
    new_song.set('Dir', song.dir)
    
    # Process each group and sort by difficulty order
    merged_steps: List[Tuple[int, ET.Element]] = []
    
    for (steps_type, difficulty), entries in steps_groups.items():
        # Resolve hash
        resolved_hash, hash_found = resolve_hash(entries, song.dir, steps_type, difficulty, hash_cache)
        
        if not hash_found and not any(e.md5_hash for e in entries):
            missing_hashes.append((difficulty, steps_type))
        
        if len(entries) > 1:
            # Merge entries
            total_scores = sum(len(e.high_scores) for e in entries)
            scores_consolidated += total_scores
            
            if not dry_run:
                new_steps = merge_steps_entries(entries, resolved_hash)
            else:
                new_steps = entries[0].element  # Just use first for dry run
            
            hash_status = f"-> '{resolved_hash}'" if hash_found else "(hash not found, left empty)"
            print(f"  Merged {len(entries)} entries for {difficulty} ({total_scores} scores) {hash_status}")
        else:
            # Single entry - just update hash if needed
            entry = entries[0]
            if entry.md5_hash != resolved_hash:
                if not dry_run:
                    new_steps = ET.Element('Steps')
                    new_steps.set('ChartType', entry.chart_type)
                    new_steps.set('Difficulty', entry.difficulty)
                    new_steps.set('MD5Hash', resolved_hash)
                    new_steps.set('StepsType', entry.steps_type)
                    
                    # Copy HighScoreList
                    hsl = entry.element.find('HighScoreList')
                    if hsl is not None:
                        new_steps.append(hsl)
                else:
                    new_steps = entry.element
                
                if hash_found:
                    print(f"  Updated hash for {difficulty}: '{entry.md5_hash}' -> '{resolved_hash}'")
                else:
                    print(f"  Hash not found for {difficulty}, keeping empty")
            else:
                new_steps = entry.element
        
        # Get difficulty order
        diff_order = DIFFICULTY_ORDER.get(difficulty, 99)
        merged_steps.append((diff_order, new_steps))
    
    # Sort by difficulty order
    merged_steps.sort(key=lambda x: x[0])
    
    # Add to song element
    for _, steps_elem in merged_steps:
        new_song.append(steps_elem)
    
    return new_song, duplicates_merged, scores_consolidated, missing_hashes


def indent_xml(elem: ET.Element, level: int = 0):
    """Add indentation to XML for pretty printing."""
    indent = "\n" + "  " * level
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = indent + "  "
        if not elem.tail or not elem.tail.strip():
            elem.tail = indent
        for child in elem:
            indent_xml(child, level + 1)
        if not child.tail or not child.tail.strip():
            child.tail = indent
    else:
        if level and (not elem.tail or not elem.tail.strip()):
            elem.tail = indent


def extract_song_scores_section(xml_content: str) -> Tuple[Optional[str], int, int]:
    """Extract the <SongScores>...</SongScores> section from XML content.
    
    Returns: (section_content, start_pos, end_pos) or (None, -1, -1) if not found.
    """
    # Find <SongScores> opening tag
    start_match = re.search(r'<SongScores\s*>', xml_content)
    if not start_match:
        return None, -1, -1
    
    # Find </SongScores> closing tag
    end_match = re.search(r'</SongScores\s*>', xml_content)
    if not end_match:
        return None, -1, -1
    
    start_pos = start_match.start()
    end_pos = end_match.end()
    
    return xml_content[start_pos:end_pos], start_pos, end_pos


def escape_xml_attr(value: str) -> str:
    """Escape special characters for XML attribute values."""
    value = value.replace('&', '&amp;')
    value = value.replace('<', '&lt;')
    value = value.replace('>', '&gt;')
    value = value.replace("'", '&apos;')
    value = value.replace('"', '&quot;')
    return value


def serialize_song_element(song_elem: ET.Element, indent: str = "  ") -> str:
    """Serialize a Song element to XML string, preserving OutFox formatting style."""
    lines = []
    
    song_dir = escape_xml_attr(song_elem.get('Dir', ''))
    lines.append(f"{indent}<Song Dir='{song_dir}'>")
    
    for steps_elem in song_elem.findall('Steps'):
        lines.extend(serialize_steps_element(steps_elem, indent + indent))
    
    lines.append(f"{indent}</Song>")
    
    return '\n'.join(lines)


def serialize_steps_element(steps_elem: ET.Element, indent: str = "    ") -> List[str]:
    """Serialize a Steps element to XML string lines."""
    lines = []
    
    # Build Steps opening tag with attributes in OutFox order
    chart_type = steps_elem.get('ChartType', '')
    difficulty = steps_elem.get('Difficulty', '')
    md5_hash = steps_elem.get('MD5Hash', '')
    steps_type = steps_elem.get('StepsType', '')
    
    lines.append(f"{indent}<Steps ChartType='{chart_type}' Difficulty='{difficulty}' MD5Hash='{md5_hash}' StepsType='{steps_type}'>")
    
    # Serialize HighScoreList
    hsl = steps_elem.find('HighScoreList')
    if hsl is not None:
        lines.append(f"{indent}<HighScoreList>")
        
        # NumTimesPlayed
        ntp = hsl.find('NumTimesPlayed')
        if ntp is not None and ntp.text:
            lines.append(f"{indent}<NumTimesPlayed>{ntp.text}</NumTimesPlayed>")
        
        # LastPlayed
        lp = hsl.find('LastPlayed')
        if lp is not None and lp.text:
            lines.append(f"{indent}<LastPlayed>{lp.text}</LastPlayed>")
        
        # HighGrade
        hg = hsl.find('HighGrade')
        if hg is not None and hg.text:
            lines.append(f"{indent}<HighGrade>{hg.text}</HighGrade>")
        
        # HighScores
        for hs in hsl.findall('HighScore'):
            lines.extend(serialize_highscore_element(hs, indent))
        
        lines.append(f"{indent}</HighScoreList>")
    
    lines.append(f"{indent}</Steps>")
    
    return lines


def serialize_highscore_element(hs_elem: ET.Element, indent: str) -> List[str]:
    """Serialize a HighScore element to XML string lines."""
    lines = []
    lines.append(f"{indent}<HighScore>")
    
    # Serialize all child elements in order
    for child in hs_elem:
        if len(child) > 0:  # Has children (like TapNoteScores, HoldNoteScores, RadarValues)
            lines.append(f"{indent}<{child.tag}>")
            for subchild in child:
                text = subchild.text if subchild.text else ''
                lines.append(f"{indent}<{subchild.tag}>{text}</{subchild.tag}>")
            lines.append(f"{indent}</{child.tag}>")
        else:
            text = child.text if child.text else ''
            lines.append(f"{indent}<{child.tag}>{text}</{child.tag}>")
    
    lines.append(f"{indent}</HighScore>")
    return lines


def process_stats_xml(stats_path: str, save_dir: str, dry_run: bool = False):
    """Main processing function - surgically modifies only SongScores section."""
    
    stats_path = Path(stats_path)
    save_dir = Path(save_dir)
    
    if not stats_path.exists():
        print(f"Error: Stats.xml not found: {stats_path}")
        return
    
    if not save_dir.exists():
        print(f"Error: Save directory not found: {save_dir}")
        return
    
    print(f"Processing: {stats_path}")
    print(f"Save directory: {save_dir}")
    if dry_run:
        print("DRY RUN - no changes will be made")
    print()
    
    # Load hash cache from song.db
    hash_cache = load_hash_cache_from_songdb(save_dir)
    
    # Read original file content
    with open(stats_path, 'r', encoding='utf-8') as f:
        original_content = f.read()
    
    # Extract SongScores section
    song_scores_section, section_start, section_end = extract_song_scores_section(original_content)
    if song_scores_section is None:
        print("Error: No SongScores section found in Stats.xml")
        return
    
    # Parse only the SongScores section (no numeric tag issues here)
    try:
        song_scores_root = ET.fromstring(song_scores_section)
    except ET.ParseError as e:
        print(f"Error parsing SongScores section: {e}")
        return
    
    # Process all songs
    total_songs = 0
    total_duplicates = 0
    total_scores = 0
    modified_songs: List[Tuple[str, ET.Element]] = []  # (song_dir, new_song_elem)
    songs_with_missing_hashes: List[Tuple[str, List[Tuple[str, str]]]] = []  # (song_dir, [(difficulty, steps_type)])
    
    all_songs: List[Tuple[str, ET.Element]] = []  # All songs for full rebuild
    
    for song_elem in song_scores_root.findall('Song'):
        song = SongEntry(song_elem)
        total_songs += 1
        
        # Check if this song needs processing
        has_duplicates = False
        has_empty_hash = False
        has_old_format = False
        steps_keys = set()
        
        for steps in song.steps:
            key = steps.get_key()
            if key in steps_keys:
                has_duplicates = True
            steps_keys.add(key)
            if not steps.md5_hash:
                has_empty_hash = True
            if steps.uses_old_format:
                has_old_format = True
        
        if has_duplicates or has_empty_hash or has_old_format:
            print(f"Processing: {song.dir}")
            new_song, dups, scores, missing_hashes = process_song(song, hash_cache, dry_run)
            total_duplicates += dups
            total_scores += scores
            if missing_hashes:
                songs_with_missing_hashes.append((song.dir, missing_hashes))
            modified_songs.append((song.dir, new_song))
            all_songs.append((song.dir, new_song))
        else:
            # Keep original song but still add to all_songs for full rebuild
            all_songs.append((song.dir, song_elem))
    
    # If no changes needed, exit early
    if not modified_songs:
        print()
        print("=" * 50)
        print("Summary:")
        print(f"  Songs processed: {total_songs}")
        print("  No changes needed.")
        return
    
    # Rebuild the entire SongScores section to ensure consistent format
    if not dry_run:
        # Create backup
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = stats_path.with_suffix(f'.xml.backup.{timestamp}')
        shutil.copy2(stats_path, backup_path)
        print()
        print(f"Backup created: {backup_path}")
        
        # Build new SongScores section from all songs
        new_song_scores_lines = ["<SongScores>"]
        for song_dir, song_elem in all_songs:
            new_song_scores_lines.append(serialize_song_element(song_elem))
        new_song_scores_lines.append("</SongScores>")
        new_song_scores_content = "\n".join(new_song_scores_lines)
        
        # Replace the SongScores section in the original file
        new_content = (
            original_content[:section_start] + 
            new_song_scores_content + 
            original_content[section_end:]
        )
        
        # Write output
        with open(stats_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        
        print()
        print(f"Stats.xml updated successfully!")
    
    # Summary
    print()
    print("=" * 50)
    print("Summary:")
    print(f"  Songs processed: {total_songs}")
    print(f"  Songs modified: {len(modified_songs)}")
    print(f"  Duplicate entries merged: {total_duplicates}")
    print(f"  Scores consolidated: {total_scores}")
    
    # List songs with missing hashes
    if songs_with_missing_hashes:
        total_missing = sum(len(charts) for _, charts in songs_with_missing_hashes)
        print(f"  WARNING: Hashes not found (left empty): {total_missing}")
        print()
        print("Songs with missing hashes (play these songs to generate hashes):")
        for song_dir, missing_charts in songs_with_missing_hashes:
            print(f"  {song_dir}")
            for difficulty, steps_type in missing_charts:
                print(f"    - {difficulty} ({steps_type})")
    
    if dry_run:
        print()
        print("This was a dry run. No changes were made.")


def main():
    parser = argparse.ArgumentParser(
        description='Fix Stats.xml by merging duplicate Steps entries and resolving empty MD5 hashes'
    )
    parser.add_argument(
        '--stats', 
        required=True,
        help='Path to Stats.xml file to fix'
    )
    parser.add_argument(
        '--save-dir',
        required=True, 
        help='Path to Save directory (contains LocalProfiles)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be changed without modifying files'
    )
    
    args = parser.parse_args()
    
    process_stats_xml(args.stats, args.save_dir, args.dry_run)


if __name__ == '__main__':
    main()
