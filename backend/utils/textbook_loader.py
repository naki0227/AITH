import os
import json
import glob

# Map text_id (from API) to directory path (relative to backend/data/textbooks/)
TEXTBOOK_MAPPING = {
    # Math JHS
    "math_v1": "math/jhs1",
    "math_v2": "math/jhs2",
    "math_v3": "math/jhs3",
    
    # Placeholder mappings for future expansion
    "english_v1": "english/jhs1",
    "science_bio": "science/biology",
    "social_history": "social/history",
    # Add mapping for all planned subjects here...
}

BASE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data/textbooks")

def load_textbook(text_id: str):
    """
    Load all JSON unit files for a given text_id and aggregate them into a single Textbook object dict.
    """
    if text_id not in TEXTBOOK_MAPPING:
        return None

    rel_path = TEXTBOOK_MAPPING[text_id]
    target_dir = os.path.join(BASE_DIR, rel_path)
    
    if not os.path.exists(target_dir):
        # Fallback: if directory doesn't exist yet, return None to let main.py fall back to legacy strings if needed
        # OR raise error if strictly migrating. For now, return None.
        return None

    # Find all json files
    json_files = glob.glob(os.path.join(target_dir, "*.json"))
    units = []

    for fpath in json_files:
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                data = json.load(f)
                units.append(data)
        except Exception as e:
            print(f"Error loading {fpath}: {e}")
            continue

    # Sort units by 'order'
    units.sort(key=lambda x: x.get("order", 999))

    # Aggregate chapters
    all_chapters = []
    textbook_title = "Unknown Textbook"
    subject = "Unknown"

    if units:
        # Use metadata from the first unit or define a separate meta.json
        # For now, quick hack: infer from mapping or first unit?
        # Ideally we should have a 'textbook_meta.json' or similar. 
        # But 'unit_title' is not 'textbook_title'.
        # We will hardcode titles in main.py wrapper or add a separate mapping.
        pass

    for unit in units:
        unit_title = unit.get("unit_title", "")
        # Create a "Unit Cover" chapter or just append chapters?
        # Let's append chapters, but maybe prefix chapter titles with Unit name if needed.
        # Ideally, we want a Unit hierarchy, but the frontend expects a flat list of chapters.
        # We will add a "Separator" chapter or just list them.
        
        for chapter in unit.get("chapters", []):
            # Process sections to generate monolythic markdown content
            sections = chapter.get("sections", [])
            full_markdown = generate_markdown_from_sections(sections)
            
            # Append Unit info to Chapter title for clarity if needed, or just use Chapter title
            # chapter_title = f"[{unit_title}] {chapter.get('title')}"
            chapter_title = chapter.get("title")
            
            all_chapters.append({
                "title": chapter_title,
                "content": full_markdown
            })
            
    return all_chapters


def generate_markdown_from_sections(sections):
    """
    Convert a list of Section objects (with content_blocks) into a single Markdown string.
    """
    md_lines = []

    for section in sections:
        title = section.get("title", "")
        if title:
            md_lines.append(f"## {title}")
            md_lines.append("")
        
        for block in section.get("content_blocks", []):
            b_type = block.get("type", "text")
            
            if b_type == "introduction":
                md_lines.append(block.get("text", ""))
                md_lines.append("")
            
            elif b_type == "definition":
                term = block.get("term", "")
                defn = block.get("definition", "")
                md_lines.append(f"**{term}**: {defn}")
                md_lines.append("")

            elif b_type == "explanation":
                md_lines.append(block.get("markdown", ""))
                md_lines.append("")
            
            elif b_type == "point":
                # Important Point box style
                p_title = block.get("title", "Point")
                content = block.get("content", "")
                md_lines.append(f"### 💡 {p_title}")
                md_lines.append(content)
                md_lines.append("")
            
            elif b_type == "example_problem":
                p_title = block.get("title", "例題")
                prob = block.get("problem", "")
                steps = block.get("solution_steps", [])
                
                md_lines.append(f"### 📝 {p_title}")
                md_lines.append(prob)
                md_lines.append("")
                md_lines.append("**【解き方】**")
                for step in steps:
                    md_lines.append(f"- {step}")
                md_lines.append("")
                md_lines.append("---")
                md_lines.append("")

            elif b_type == "exercise":
                md_lines.append("### ✏️ 練習問題")
                problems = block.get("problems", [])
                for i, p in enumerate(problems, 1):
                    q = p.get("q", "")
                    a = p.get("a", "")
                    md_lines.append(f"**({i})** {q}")
                    # Hidden answer or standard? For now, standard.
                    md_lines.append(f"   (答: {a})")
                md_lines.append("")

    return "\n".join(md_lines)
