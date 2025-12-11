#!/usr/bin/env python3
"""
Extract all MD5 chart hashes from song.db cache.
The cache stores hashes in #CHARTHASH: tags within the compressed data.
"""

import sqlite3
import lz4.block
import re
import json
from pathlib import Path

db_path = Path(r"C:\Games\OutFox 0.5.0 Alpha Win64 aFinal\Cache\song.db")
output_path = Path(r"C:\Games\OutFox 0.5.0 Alpha Win64 aFinal\Save\songdb_hash_cache.json")

def extract_hashes_from_cache():
    """Extract all chart hashes from song.db."""
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get all songs
    cursor.execute("SELECT FILENAME, FULLSIZE, DATA FROM SONGS")
    rows = cursor.fetchall()
    
    print(f"Processing {len(rows)} song cache entries...")
    
    # Hash cache: (song_dir, steps_type, difficulty) -> md5_hash
    hash_cache = {}
    errors = 0
    charts_found = 0
    
    for filename, fullsize, data in rows:
        try:
            # Decompress
            decompressed = lz4.block.decompress(data, uncompressed_size=fullsize)
            text = decompressed.decode('utf-8', errors='replace')
            
            # Extract song dir
            song_dir_match = re.search(r'#SONGDIR:([^;]+);', text)
            if not song_dir_match:
                continue
            song_dir = song_dir_match.group(1)
            
            # Find all chart sections
            # Split by #NOTEDATA:; to get individual charts
            sections = text.split('#NOTEDATA:;')
            
            for section in sections[1:]:  # Skip header
                # Extract chart info
                hash_match = re.search(r'#CHARTHASH:([a-f0-9]{32});', section, re.IGNORECASE)
                steps_type_match = re.search(r'#STEPSTYPE:([^;]+);', section)
                difficulty_match = re.search(r'#DIFFICULTY:([^;]+);', section)
                
                if hash_match and steps_type_match and difficulty_match:
                    md5_hash = hash_match.group(1).lower()
                    steps_type = steps_type_match.group(1)
                    difficulty = difficulty_match.group(1)
                    
                    # Convert steps_type to Stats.xml format
                    # e.g., "dance-single" -> "StepsType_Dance_Single"
                    steps_type_xml = "StepsType_" + "_".join(
                        word.capitalize() for word in steps_type.split('-')
                    )
                    
                    key = f"{song_dir}|{steps_type_xml}|{difficulty}"
                    hash_cache[key] = md5_hash
                    charts_found += 1
                    
        except Exception as e:
            errors += 1
            if errors <= 5:
                print(f"Error processing {filename}: {e}")
    
    conn.close()
    
    print(f"\nExtracted {charts_found} chart hashes from {len(rows)} songs")
    if errors > 0:
        print(f"Errors: {errors}")
    
    # Save to JSON
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(hash_cache, f, indent=2, sort_keys=True)
    
    print(f"Hash cache saved to: {output_path}")
    
    # Show sample
    print("\nSample entries:")
    for i, (key, hash_val) in enumerate(list(hash_cache.items())[:5]):
        print(f"  {key}: {hash_val}")
    
    # Verify In Bloom Easy
    test_key = "/Songs/Z2024-Rajeious Unique Pack/In Bloom/|StepsType_Dance_Single|Easy"
    if test_key in hash_cache:
        print(f"\nVerification - In Bloom Easy: {hash_cache[test_key]}")
        print(f"Expected: eb04fefaa986b16b28f5c6303a4f4c3d")
        print(f"Match: {hash_cache[test_key] == 'eb04fefaa986b16b28f5c6303a4f4c3d'}")
    
    return hash_cache


if __name__ == "__main__":
    extract_hashes_from_cache()
