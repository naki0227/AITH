import os
import firebase_admin
from firebase_admin import credentials, firestore
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Body
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import google.generativeai as genai
from dotenv import load_dotenv
import json
import re
from datetime import datetime, timezone, timedelta
from typing import Optional, List

# Load environment variables
load_dotenv(dotenv_path="../.env")

app = FastAPI()

# CORS setup - Allow all origins for mobile app compatibility
# In production, you may want to restrict to specific domains
allowed_origins = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins if allowed_origins != ["*"] else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount uploads directory
os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# Firebase Setup
# Priority: 1. FIREBASE_CREDENTIALS env var (JSON string) 2. Local file
firebase_creds_json = os.getenv("FIREBASE_CREDENTIALS")
if firebase_creds_json:
    # Production: Load from environment variable (JSON string)
    cred_dict = json.loads(firebase_creds_json)
    cred = credentials.Certificate(cred_dict)
else:
    # Development: Load from local file
    cred = credentials.Certificate("aith-ai-tutor-firebase-adminsdk-fbsvc-de5e0f9c69.json")

try:
    firebase_admin.get_app()
except ValueError:
    firebase_admin.initialize_app(cred)

db = firestore.client()

# Gemini Setup
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise ValueError("GEMINI_API_KEY not found in environment variables")

genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel('gemini-2.5-flash')

COMMON_INSTRUCTION = """
あなたは「AITH（AI Tutor for Homework）」のAIチューターです。
ユーザーから送られてきた画像やテキストを解析し、学習のサポートを行ってください。

**重要: 出力フォーマット (Strict JSON Protocol)**
回答は**必ず**以下のJSONフォーマットのみで出力してください。Markdownのコードブロック（```json ... ```）は使用せず、生のJSON文字列だけを返してください。

**重要: LaTeXのバックスラッシュについて**
JSON文字列の中でLaTeXコマンドを使用する場合、バックスラッシュは**必ず2つ重ねて**エスケープしてください。
- 悪い例: `"content": "S = \sqrt{s(s-a)}"`  (JSONパースエラーになります)
- 良い例: `"content": "S = \\sqrt{s(s-a)}"`

**重要: 数式の区切り文字 ($) について**
数式は**必ず** `$` で囲んでください。
- 悪い例: The equation is y = ax^2 + b.
- 良い例: The equation is $y = ax^2 + b$.
- 悪い例: Use \\sqrt{2} to solve it.
- 良い例: Use $\\sqrt{2}$ to solve it.
- 悪い例: Where a is 5 and b is 3.
- 良い例: Where $a$ is $5$ and $b$ is $3$.

裸のLaTeXコマンド（`\\frac`, `\\times` など）や数式（`x^2`）を `$` なしで出力することは**厳禁**です。

```json
{
  "blocks": [
    {
      "type": "text",
      "content": "解説テキスト。ここはMarkdown（**太字**やインライン数式 $x$ など）が使えます。"
    },
    {
      "type": "latex_block",
      "content": "S = \\\\sqrt{s(s-a)(s-b)(s-c)}"
    },
    {
      "type": "svg",
      "content": "<svg viewBox=\\"0 0 300 300\\">...</svg>"
    }
  ],
  "challenge": {
     "question": "理解度を確認するための類題...",
     "options": ["選択肢A", "選択肢B", "選択肢C", "選択肢D"],
     "answer_index": 0,
     "explanation": "正解の解説..."
  }
}
```

**ブロックの使い分け**:
1. **text**: 通常の解説文。
   - インライン数式は `$x$` のように単一のドル記号で囲む。
   - `\\sqrt` などのLaTeXコマンドを裸で書くのは厳禁。
2. **latex_block**: 独立した数式（行単位で大きく表示したい場合）。
   - `$$` は不要。中身のLaTeXコードのみ記述する（例: `y = ax^2`）。
3. **svg**: 幾何学図形やグラフ。
   - `viewBox="0 0 300 300"` を必須とする。
   - 複雑な `<path>` (Arcなど) は禁止。`<line>`, `<circle>`, `<polygon>`, `<text>` でシンプルに描く。
   - 線は黒 (`stroke="black"`)、太さ2 (`stroke-width="2"`)。

**Challengeデータのルール**:
- 解説の後には、必ず理解度チェックのための「類題」を作成し、`challenge` フィールドに含めること。
"""

SYSTEM_INSTRUCTIONS = {
    "student": """
あなたは中高生向けの親しみやすい家庭教師AIです。
- 相手は中学生や高校生です。
- 絵文字（😊, ✨, 👍など）を多めに使い、明るく励ますようなトーンで話してください。
- 難しい専門用語は避け、噛み砕いて説明してください。
- 答えをすぐに教えるのではなく、ヒントを出して考えさせるように導いてください。
- 「すごい！」「その調子！」など、褒める言葉を積極的に使ってください。
""",
    "university": """
あなたは大学生向けの論理的なTA（ティーチングアシスタント）AIです。
- 相手は就職活動や研究に取り組む大学生です。
- 結論から先に述べる（PREP法など）ことを意識し、効率的かつ論理的に解説してください。
- 専門用語は適切に使用し、必要であれば学術的な背景や参考文献についても言及してください。
- SPIや試験対策など、実利的な視点でのアドバイスも歓迎されます。
- 無駄な装飾は避け、知的なトーンを保ってください。
""",
    "adult": """
あなたは社会人向けのプロフェッショナルなスキルアップコーチAIです。
- 相手は忙しいビジネスパーソンです。時間は有限であるという前提で接してください。
- 敬語を使い、丁寧かつ簡潔に、要点のみを伝えてください。
- 実務ですぐに使える知識や、ビジネスシーンでの応用例を重視してください。
- 資格試験対策などでは、効率的な学習法や合格への最短ルートを提示してください。
- 余計な雑談は省き、プロフェッショナルな態度を貫いてください。
"""
}

def clean_json_text(text: str) -> str:
    # 1. コードブロック削除
    match = re.search(r'```json\s*(.*?)\s*```', text, re.DOTALL)
    if match:
        text = match.group(1)
    else:
        start = text.find('{')
        end = text.rfind('}')
        if start != -1 and end != -1:
            text = text[start:end+1]

    # 2. バックスラッシュの正規化（修正版）
    # 連続するバックスラッシュ（\や\\\など）が、有効なエスケープ文字（/ " \ n u）の前以外にある場合、
    # 強制的に「2つ（\\）」に統一する。
    # これにより \frac -> \\frac, \\\frac -> \\frac, \ -> \\ となり、
    # かつ \n や \" は破壊せずに保持する。
    text = re.sub(r'\\+(?![/u"\\n])', r'\\\\', text)

    return text

def find_balanced_brace_end(text, start_index):
    if start_index >= len(text) or text[start_index] != '{':
        return None
    depth = 0
    for i in range(start_index, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return i + 1
    return None

def fix_latex_delimiters(text):
    output = []
    i = 0
    n = len(text)
    
    while i < n:
        if text[i] == '$':
            output.append('$')
            i += 1
            while i < n and text[i] != '$':
                output.append(text[i])
                i += 1
            if i < n:
                output.append('$')
                i += 1
            continue
            
        if text[i] == '\\':
            # Check for \frac
            if text[i:].startswith('\\frac'):
                j = i + 5
                while j < n and text[j].isspace(): j += 1
                arg1_end = find_balanced_brace_end(text, j)
                if arg1_end:
                    k = arg1_end
                    while k < n and text[k].isspace(): k += 1
                    arg2_end = find_balanced_brace_end(text, k)
                    if arg2_end:
                        output.append('$')
                        # Strip inner $ to prevent nested math mode errors
                        content = text[i:arg2_end].replace('$', '')
                        output.append(content)
                        output.append('$')
                        i = arg2_end
                        continue
            
            # Check for \sqrt
            elif text[i:].startswith('\\sqrt'):
                j = i + 5
                while j < n and text[j].isspace(): j += 1
                if j < n and text[j] == '[':
                    while j < n and text[j] != ']': j += 1
                    if j < n: j += 1
                while j < n and text[j].isspace(): j += 1
                arg_end = find_balanced_brace_end(text, j)
                if arg_end:
                    output.append('$')
                    # Strip inner $
                    content = text[i:arg_end].replace('$', '')
                    output.append(content)
                    output.append('$')
                    i = arg_end
                    continue

            # Generic command \cmd or \cmd{arg}
            match = re.match(r'^(\\[a-zA-Z]+)', text[i:])
            if match:
                cmd = match.group(1)
                j = i + len(cmd)
                k = j
                while k < n and text[k].isspace(): k += 1
                brace_end = find_balanced_brace_end(text, k)
                
                output.append('$')
                if brace_end:
                    # Strip inner $
                    content = text[i:brace_end].replace('$', '')
                    output.append(content)
                    i = brace_end
                else:
                    output.append(cmd)
                    i = j
                output.append('$')
                continue

        output.append(text[i])
        i += 1
        
    result = "".join(output)
    
    # Second pass: Handle x^2 patterns and simple equations
    parts = result.split('$')
    for idx in range(0, len(parts), 2):
        segment = parts[idx]
        
        # Power patterns (x^2, n^3)
        segment = re.sub(r'(?<!\\)\b([a-zA-Z0-9]+\^[a-zA-Z0-9]+)\b', r'$\1$', segment)
        
        # Simple equations (x = 5, y = -3.14)
        # Pattern: "Letter + space* + = + space* + number"
        segment = re.sub(r'\b([a-zA-Z]\s*=\s*-?\d+(\.\d+)?)\b', r'$\1$', segment)
        
        # Complex equations starting with variable assignment (x = \frac...)
        segment = re.sub(r'([a-zA-Z]\s*=\s*\\[a-zA-Z]+(?:\{.*?\})*)', r'$\1$', segment)

        parts[idx] = segment

    final_result = "$".join(parts)
    
    return final_result

def wrap_math_delimiters(data):
    """JSONデータの text ブロック内の裸の数式を $...$ で囲む"""
    if not isinstance(data, dict) or "blocks" not in data:
        return data
    
    for block in data["blocks"]:
        if block.get("type") == "text":
            block["content"] = fix_latex_delimiters(block["content"])
    return data

@app.post("/analyze_image")
async def analyze_image(
    file: UploadFile = File(...),
    mode: str = Form(...),
    text: str = Form(None)  # Optional text input
):
    if mode not in SYSTEM_INSTRUCTIONS:
        raise HTTPException(status_code=400, detail="Invalid mode. Choose from student, university, adult.")

    try:
        content = await file.read()
        system_instruction = SYSTEM_INSTRUCTIONS[mode]
        
        # Fetch user profile
        user_ref = db.collection('users').document('demo_user')
        user_doc = user_ref.get()
        if user_doc.exists:
            user_data = user_doc.to_dict()
            grade = user_data.get('grade')
            if grade:
                system_instruction += f"\n\n【重要】ユーザーの学年は「{grade}」です。この学年の知識レベルに合わせて解説してください。"

        # Construct prompt based on whether text is provided
        if text:
            user_prompt = f"ユーザーはこの画像を見ながら次の質問をしています: 「{text}」\nこの質問に答えてください。画像の内容も踏まえて解説してください。"
        else:
            user_prompt = "この画像を解析して、質問に答えてください。もし画像に質問が含まれていない場合は、画像の内容を解説してください。"

        prompt = f"{system_instruction}\n\n{COMMON_INSTRUCTION}\n\n{user_prompt}"
        
        response = model.generate_content([
            {'mime_type': file.content_type, 'data': content},
            prompt
        ], generation_config={"response_mime_type": "application/json"}) # Force JSON
        
        response_text = clean_json_text(response.text)
        
        # Parse JSON to validate and extract data for logging
        try:
            response_json = json.loads(response_text, strict=False)
            # Ensure it has the expected structure
            if "blocks" not in response_json:
                 # Fallback if AI messed up structure but returned JSON
                 response_json = {
                     "blocks": [{"type": "text", "content": response_text}],
                     "challenge": None
                 }
            
            # Apply post-processing to ensure math delimiters
            response_json = wrap_math_delimiters(response_json)

        except json.JSONDecodeError:
            # Fallback for non-JSON response
            print(f"JSON Parse Error: {response_text}")
            response_json = {
                "blocks": [{"type": "text", "content": response_text}],
                "challenge": None
            }

        # Save log to Firestore
        doc_ref = db.collection('logs').document()
        doc_ref.set({
            'user_id': 'demo_user',
            'mode': mode,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'response_json': response_json,
            'filename': file.filename,
            'user_text': text
        })

        return response_json

    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class ChatRequest(BaseModel):
    user_id: str = "demo_user" # Added user_id
    message: str
    image_data: Optional[str] = None
    persona: str = "gentle" # gentle, hot_blooded, strict
    mode: str = "student" # student, university, adult

class InsightRequest(BaseModel):
    user_id: str
    text: str

@app.post("/extract_insights")
async def extract_insights(request: InsightRequest):
    try:
        prompt = f"""
        以下のチャット履歴から、ユーザーに関する重要な情報を抽出してください。
        
        【チャット履歴】
        {request.text}
        
        以下のJSON形式で出力してください。該当なしの場合は空リストにしてください。
        {{
            "interests": ["サッカー", "ゲーム", ...],
            "weaknesses": ["二次関数", "英単語", ...],
            "goals": ["志望校合格", "英検2級", ...]
        }}
        """
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        new_insights = json.loads(clean_json_text(response.text))
        
        # Merge with existing insights in Firestore
        doc_ref = db.collection('users').document(request.user_id).collection('insights').document('profile')
        doc = doc_ref.get()
        
        current_data = doc.to_dict() if doc.exists else {"interests": [], "weaknesses": [], "goals": []}
        
        # Simple merge (append and dedup)
        for key in ["interests", "weaknesses", "goals"]:
            current_list = current_data.get(key, [])
            new_list = new_insights.get(key, [])
            merged = list(set(current_list + new_list))
            current_data[key] = merged
            
        doc_ref.set(current_data)
        
        return {"status": "success", "insights": current_data}
    except Exception as e:
        print(f"Extract Insights Error: {e}")
        # Non-blocking error for chat flow, but return error status
        return {"status": "error", "detail": str(e)}

@app.post("/chat")
async def chat(request: ChatRequest):
    try:
        # 1. Fetch User Insights & Profile
        insights_text = ""
        user_persona = request.persona # Default from request
        
        try:
            doc_ref = db.collection('users').document(request.user_id).collection('insights').document('profile')
            doc = doc_ref.get()
            if doc.exists:
                data = doc.to_dict()
                
                # Prioritize user-set persona if available
                if data.get("persona"):
                    user_persona = data.get("persona")
                
                # Construct context from both user-set and AI-extracted data
                interests = data.get("interests", [])
                if data.get("interests_raw"):
                    interests.append(data.get("interests_raw"))
                    
                goals = data.get("goals", [])
                if data.get("goal"):
                    goals.append(data.get("goal"))
                
                insights_text = f"""
【ユーザー情報】
- 興味・関心: {", ".join(list(set(interests)))}
- 苦手分野: {", ".join(data.get("weaknesses", []))}
- 目標: {", ".join(list(set(goals)))}
※これらの情報を踏まえて、例え話に使ったり、励ましたりしてください。
"""
        except Exception as e:
            print(f"Insight Fetch Error: {e}")

        # Persona System Prompts
        personas = {
            "gentle": "あなたは優しく励ましてくれる家庭教師です。丁寧な言葉遣いで、生徒を褒めながら教えてください。",
            "hot_blooded": "あなたは熱血コーチです。「気合だ！」「まだいける！」と熱く鼓舞しながら教えてください。",
            "strict": "あなたは厳格な教授です。甘えを許さず、論理的かつ厳密に指導してください。"
        }
        base_prompt = personas.get(user_persona, personas["gentle"])
        
        # Mode (Target Audience) Adjustments
        mode_instructions = {
            "student": "相手は中高生です。分かりやすく、基礎的な内容から丁寧に説明してください。数式は高校数学の範囲で記述してください。",
            "university": "相手は大学生です。専門用語を用い、理論的背景や導出過程も含めて詳細に解説してください。高度な数学的概念も使用可能です。",
            "adult": "相手は社会人です。実務的な応用や、教養としての側面を重視し、簡潔かつ論理的に説明してください。"
        }
        mode_instruction = mode_instructions.get(request.mode, mode_instructions["student"])
        
        system_prompt = f"{base_prompt}\n\n【対象読者設定】\n{mode_instruction}\n{insights_text}"

        if request.image_data:
            image_data = base64.b64decode(request.image_data)
            prompt = f"{system_prompt}\nユーザーの質問: {request.message}"
            response = model.generate_content([{'mime_type': 'image/jpeg', 'data': image_data}, prompt])
        else:
            prompt = f"{system_prompt}\nユーザーの質問: {request.message}"
            response = model.generate_content(prompt)
            
        response_text = fix_latex_delimiters(response.text)
        return {"reply": response_text}
    except Exception as e:
        print(f"Chat Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
def read_root():
    return {"message": "AITH Backend is running"}

class ProfileUpdateRequest(BaseModel):
    user_id: str
    grade: str
    persona: Optional[str] = "gentle"
    goal: Optional[str] = ""
    interests: Optional[str] = ""
    avatar: Optional[str] = "default"

@app.post("/update_profile")
async def update_profile(request: ProfileUpdateRequest):
    try:
        # Save to Firestore
        # We save to 'insights/profile' to keep it consistent with the extracted insights
        doc_ref = db.collection('users').document(request.user_id).collection('insights').document('profile')
        
        # Merge with existing data
        doc = doc_ref.get()
        current_data = doc.to_dict() if doc.exists else {}
        
        current_data['grade'] = request.grade
        current_data['persona'] = request.persona
        current_data['goal'] = request.goal # User set goal
        current_data['interests_raw'] = request.interests # User set interests text
        current_data['avatar'] = request.avatar
        
        # Also update the 'goals' and 'interests' lists if possible, or just keep raw text
        # For now, we store raw text separately to distinguish from AI extracted lists
        
        doc_ref.set(current_data, merge=True)
        
        return {"status": "success"}
    except Exception as e:
        print(f"Update Profile Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/profile/{user_id}")
async def get_profile(user_id: str):
    try:
        doc_ref = db.collection('users').document(user_id).collection('insights').document('profile')
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            return {
                "grade": data.get("grade", "中学2年生"),
                "persona": data.get("persona", "gentle"),
                "goal": data.get("goal", ""),
                "interests": data.get("interests_raw", ""),
                "avatar": data.get("avatar", "default")
            }
        else:
            return {"grade": "中学2年生", "persona": "gentle", "goal": "", "interests": "", "avatar": "default"}
    except Exception as e:
        print(f"Get Profile Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/user_data")
async def get_user_data(user_id: str = "demo_user"):
    """Get raw user data (XP, level, etc.) - different from profile settings"""
    try:
        doc_ref = db.collection('users').document(user_id)
        doc = doc_ref.get()
        if doc.exists:
            return doc.to_dict()
        else:
            return {}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/upload_material")
async def upload_material(file: UploadFile = File(...), user_id: str = Form("demo_user")):
    try:
        # Save file locally
        file_location = f"uploads/{file.filename}"
        with open(file_location, "wb") as f:
            f.write(await file.read())
        
        # Generate Summary with Gemini
        # Re-open file for reading
        with open(file_location, "rb") as f:
            content = f.read()
            
        prompt = """
        この資料（画像またはPDF）の内容を簡潔に要約し、適切なタイトルをつけてください。
        また、この資料の「教科（科目）」を推測してください（例: 数学, 英語, 理科, 社会, 国語, その他）。
        
        出力は以下のJSON形式のみでお願いします。
        {
            "title": "資料のタイトル",
            "summary": "資料の要約（100文字程度）",
            "subject": "数学"
        }
        """
        
        response = model.generate_content([
            {'mime_type': file.content_type, 'data': content},
            prompt
        ], generation_config={"response_mime_type": "application/json"})
        
        ai_data = json.loads(clean_json_text(response.text))
        
        # Save to Firestore
        doc_ref = db.collection('users').document(user_id).collection('materials').document()
        doc_ref.set({
            'title': ai_data.get('title', '無題の資料'),
            'summary': ai_data.get('summary', '要約なし'),
            'subject': ai_data.get('subject', 'その他'),
            'file_path': file_location,
            'file_type': 'image' if 'image' in file.content_type else 'pdf',
            'created_at': firestore.SERVER_TIMESTAMP
        })
        
        return {"status": "success", "message": "Material uploaded", "id": doc_ref.id}
        
    except Exception as e:
        print(f"Upload Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/materials")
async def get_materials(user_id: str = "demo_user"):
    try:
        docs = db.collection('users').document(user_id).collection('materials').order_by('created_at', direction=firestore.Query.DESCENDING).stream()
        materials = []
        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id
            # Convert timestamp to string for JSON serialization
            if 'created_at' in data and data['created_at']:
                data['created_at'] = data['created_at'].isoformat()
            materials.append(data)
        return materials
    except Exception as e:
        print(f"Get Materials Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class DrillRequest(BaseModel):
    user_id: str
    material_id: str

@app.post("/generate_drill")
async def generate_drill(request: DrillRequest):
    try:
        # 1. Fetch material info
        material_ref = db.collection('users').document(request.user_id).collection('materials').document(request.material_id)
        material_doc = material_ref.get()
        
        if not material_doc.exists:
            raise HTTPException(status_code=404, detail="Material not found")
            
        material_data = material_doc.to_dict()
        file_path = material_data.get('file_path')
        
        if not file_path or not os.path.exists(file_path):
             raise HTTPException(status_code=404, detail="File not found")

        # 2. Read file content
        with open(file_path, "rb") as f:
            content = f.read()
            
        # 3. Generate Drill with Gemini
        prompt = """
        この資料の内容に基づいて、理解度を確認するための「4択クイズ」を5問作成してください。
        
        出力は以下のJSON形式のみでお願いします。
        {
            "questions": [
                {
                    "question": "問題文（数式は $...$ で囲む）",
                    "options": ["選択肢A", "選択肢B", "選択肢C", "選択肢D"],
                    "answer_index": 0,
                    "explanation": "解説（数式は $...$ で囲む）"
                },
                ...
            ]
        }
        """
        
        # Determine mime type
        mime_type = 'application/pdf' if file_path.endswith('.pdf') else 'image/jpeg'
        
        response = model.generate_content([
            {'mime_type': mime_type, 'data': content},
            prompt
        ], generation_config={"response_mime_type": "application/json"})
        
        drill_data = json.loads(clean_json_text(response.text))
        
        # Post-process math delimiters in questions and explanations
        if "questions" in drill_data:
            for q in drill_data["questions"]:
                q["question"] = fix_latex_delimiters(q["question"])
                q["explanation"] = fix_latex_delimiters(q["explanation"])
                q["options"] = [fix_latex_delimiters(opt) for opt in q["options"]]

        # 4. Save Drill to Firestore
        drill_ref = material_ref.collection('drills').document()
        drill_ref.set({
            'questions': drill_data.get('questions', []),
            'created_at': firestore.SERVER_TIMESTAMP
        })
        
        return {"status": "success", "drill_id": drill_ref.id, "drill": drill_data}

    except Exception as e:
        print(f"Generate Drill Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class StudyLogRequest(BaseModel):
    user_id: str
    type: str # "drill" or "chat"
    subject: str
    duration_seconds: int

@app.post("/record_study_log")
async def record_study_log(log: StudyLogRequest):
    try:
        # Save to Firestore
        doc_ref = db.collection('users').document(log.user_id).collection('study_logs').document()
        doc_ref.set({
            'subject': log.subject,
            'duration_seconds': log.duration_seconds,
            'timestamp': datetime.now(timezone.utc)
        })
        
        # --- Gamification Logic ---
        user_ref = db.collection('users').document(log.user_id)
        user_doc = user_ref.get()
        
        current_xp = 0
        if user_doc.exists:
            current_xp = user_doc.to_dict().get('xp', 0)
            
        # Award XP: 1 XP per 10 seconds of study
        earned_xp = int(log.duration_seconds / 10)
        new_xp = current_xp + earned_xp
        
        # Calculate Level (Simple: Level = XP // 100 + 1)
        new_level = (new_xp // 100) + 1
        
        user_ref.set({
            'xp': new_xp,
            'level': new_level,
            'last_study_at': datetime.now(timezone.utc)
        }, merge=True)
        
        return {
            "status": "success", 
            "earned_xp": earned_xp,
            "current_xp": new_xp,
            "level": new_level
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/user_stats/{user_id}")
async def get_user_stats(user_id: str):
    try:
        user_ref = db.collection('users').document(user_id)
        user_doc = user_ref.get()
        
        if not user_doc.exists:
            # Initialize new user
            return {"xp": 0, "level": 1, "streak": 0}
            
        data = user_doc.to_dict()
        xp = data.get('xp', 0)
        level = data.get('level', 1)
        
        # Calculate progress to next level
        # Level N starts at (N-1)*100 XP
        # Level N+1 starts at N*100 XP
        current_level_start_xp = (level - 1) * 100
        next_level_start_xp = level * 100
        xp_in_level = xp - current_level_start_xp
        required_xp = next_level_start_xp - current_level_start_xp # Always 100 in this simple model
        progress = xp_in_level / required_xp
        
        return {
            "xp": xp,
            "level": level,
            "progress": progress,
            "next_level_xp": next_level_start_xp - xp
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/analytics")
async def get_analytics(user_id: str):
    try:
        # Get logs for the last 7 days
        # Note: Firestore query capabilities are limited, so we might fetch more and filter in python for MVP
        # Or just fetch all logs for now (assuming small volume for demo)
        logs_ref = db.collection('users').document(user_id).collection('study_logs')
        docs = logs_ref.stream()
        
        total_study_time = 0
        subject_breakdown = {}
        daily_study_time = [0] * 7 # Last 7 days (0=Today, 6=6 days ago)
        
        now = datetime.now(timezone.utc)
        
        for doc in docs:
            data = doc.to_dict()
            duration = data.get('duration_seconds', 0)
            subject = data.get('subject', 'その他')
            timestamp = data.get('timestamp')
            
            # Total Time
            total_study_time += duration
            
            # Subject Breakdown
            subject_breakdown[subject] = subject_breakdown.get(subject, 0) + duration
            
            # Daily Breakdown
            if timestamp:
                # Handle Firestore timestamp
                log_date = timestamp.date()
                days_diff = (now.date() - log_date).days
                if 0 <= days_diff < 7:
                    daily_study_time[days_diff] += duration
        
        # Reverse daily_study_time to be [6 days ago, ..., Today] for chart
        daily_study_time.reverse()

        return {
            "total_study_time": total_study_time,
            "subject_breakdown": subject_breakdown,
            "daily_study_time": daily_study_time
        }
    except Exception as e:
        print(f"Analytics Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class MockExamRequest(BaseModel):
    user_id: str
    subject: str = "総合" # Math, English, or "General"
    grade: str = "中学2年生"

@app.post("/generate_mock_exam")
async def generate_mock_exam(request: MockExamRequest):
    try:
        prompt = f"""
        {request.grade}レベルの「{request.subject}」の模試（小テスト）を作成してください。
        問題数は5問です。4択問題形式でお願いします。
        
        出力は以下のJSON形式のみでお願いします。
        {{
            "questions": [
                {{
                    "question": "問題文（数式は $...$ で囲む）",
                    "options": ["選択肢A", "選択肢B", "選択肢C", "選択肢D"],
                    "answer_index": 0,
                    "explanation": "解説（数式は $...$ で囲む）"
                }},
                ...
            ]
        }}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        exam_data = json.loads(clean_json_text(response.text))
        
        # Post-process math delimiters
        if "questions" in exam_data:
            for q in exam_data["questions"]:
                q["question"] = fix_latex_delimiters(q["question"])
                q["explanation"] = fix_latex_delimiters(q["explanation"])
                q["options"] = [fix_latex_delimiters(opt) for opt in q["options"]]
        
        return {"status": "success", "exam": exam_data}

    except Exception as e:
        print(f"Generate Mock Exam Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/analyze_exam_schedule")
async def analyze_exam_schedule(file: UploadFile = File(...)):
    try:
        content = await file.read()
        
        prompt = """
        この画像は学校の「試験範囲表」または「試験日程表」です。
        以下の情報を抽出してJSON形式で出力してください。
        
        1. 試験名（例: 2学期期末テスト）
        2. 試験開始日（YYYY-MM-DD形式。年が不明な場合は現在の年2024または2025を補完）
        3. 各教科の試験範囲（教科名と範囲の説明）
        
        出力フォーマット:
        {
            "exam_name": "試験名",
            "start_date": "2024-12-20",
            "scopes": [
                {"subject": "数学", "range": "教科書 P30〜45, ワーク P20〜30"},
                {"subject": "英語", "range": "Lesson 5, 単語帳 P10〜20"}
            ]
        }
        """
        
        response = model.generate_content([
            {'mime_type': file.content_type, 'data': content},
            prompt
        ], generation_config={"response_mime_type": "application/json"})
        
        result = json.loads(clean_json_text(response.text))
        return result

    except Exception as e:
        print(f"Analyze Exam Schedule Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class CreatePlanRequest(BaseModel):
    user_id: str
    exam_name: str
    start_date: str
    scopes: list[dict]

@app.post("/create_study_plan")
async def create_study_plan(request: CreatePlanRequest):
    try:
        # Calculate days remaining
        exam_date = datetime.strptime(request.start_date, "%Y-%m-%d").date()
        today = datetime.now(timezone.utc).date() # Use UTC date for simplicity or JST if configured
        days_remaining = (exam_date - today).days
        
        if days_remaining < 1:
             # Fallback if exam is today or past
             days_remaining = 1

        prompt = f"""
        試験名: {request.exam_name}
        試験日: {request.start_date} (あと{days_remaining}日)
        
        試験範囲:
        {json.dumps(request.scopes, ensure_ascii=False)}
        
        今日({today})から試験前日までの「日割り学習計画」を作成してください。
        無理のない範囲で、全ての範囲を網羅するようにしてください。
        
        出力フォーマット(JSON):
        {{
            "plan": [
                {{
                    "date": "2024-12-10",
                    "tasks": ["数学: 教科書P30-35", "英語: 単語10個"]
                }},
                ...
            ]
        }}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        plan_data = json.loads(clean_json_text(response.text))
        
        # Save to Firestore
        plan_ref = db.collection('users').document(request.user_id).collection('exam_plans').document()
        plan_ref.set({
            'exam_name': request.exam_name,
            'exam_date': request.start_date, # Store as string for simplicity or convert to timestamp
            'scopes': request.scopes,
            'daily_plan': plan_data.get('plan', []),
            'created_at': firestore.SERVER_TIMESTAMP,
            'is_active': True
        })
        
        return {"status": "success", "plan_id": plan_ref.id, "plan": plan_data}

    except Exception as e:
        print(f"Create Study Plan Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/active_exam_plan")
async def get_active_exam_plan(user_id: str = "demo_user"):
    try:
        # Get the most recent active plan
        docs = db.collection('users').document(user_id).collection('exam_plans')\
            .where(filter=firestore.FieldFilter('is_active', '==', True))\
            .order_by('created_at', direction=firestore.Query.DESCENDING)\
            .limit(1).stream()
            
        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id
            return data
            
        return None # No active plan

    except Exception as e:
        print(f"Get Active Plan Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Weakness Overcoming (Spaced Repetition) ---

class MistakeRegisterRequest(BaseModel):
    user_id: str
    questions: List[dict] # List of question objects

@app.post("/register_mistakes")
async def register_mistakes(request: MistakeRegisterRequest):
    try:
        batch = db.batch()
        for q in request.questions:
            doc_ref = db.collection('users').document(request.user_id).collection('mistakes').document()
            batch.set(doc_ref, {
                'question': q['question'],
                'options': q['options'],
                'answer_index': q['answer_index'],
                'explanation': q['explanation'],
                'subject': q.get('subject', 'General'),
                'created_at': firestore.SERVER_TIMESTAMP,
                'next_review_at': datetime.now(timezone.utc) + timedelta(days=1), # First review tomorrow
                'review_level': 0 # 0: New, 1: 1d, 2: 3d, 3: 7d, 4: 14d, 5: Done
            })
        batch.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"Register Mistakes Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/review_questions")
async def get_review_questions(user_id: str = "demo_user"):
    try:
        now = datetime.now(timezone.utc)
        docs = db.collection('users').document(user_id).collection('mistakes')\
            .where(filter=firestore.FieldFilter('next_review_at', '<=', now))\
            .limit(10).stream() # Limit to 10 questions per session
            
        questions = []
        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id
            # Convert timestamp to string for JSON
            if 'next_review_at' in data:
                data['next_review_at'] = data['next_review_at'].isoformat()
            if 'created_at' in data:
                data['created_at'] = data['created_at'].isoformat()
            questions.append(data)
            
        # Generate variants for Math questions
        math_indices = [i for i, q in enumerate(questions) if q.get('subject') in ['数学', 'Math', '算数']]
        
        if math_indices:
            try:
                prompt = "以下の数学の問題の「数値を変えた類題」を作成してください。論理や解法は同じままにしてください。\n\n"
                for i, idx in enumerate(math_indices):
                    q = questions[idx]
                    prompt += f"--- 問題 {i+1} ---\n"
                    prompt += f"問題: {q['question']}\n"
                    prompt += f"選択肢: {q['options']}\n"
                    prompt += f"正解: {q['options'][q['answer_index']]}\n"
                    prompt += f"解説: {q['explanation']}\n\n"

                prompt += """
                出力は以下のJSON形式のみでお願いします。順序は入力と同じにしてください。
                {
                    "variants": [
                        {
                            "question": "問題文（数式は $...$ で囲む）",
                            "options": ["選択肢A", ...],
                            "answer_index": 0,
                            "explanation": "解説（数式は $...$ で囲む）"
                        },
                        ...
                    ]
                }
                """
                
                response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
                variants_data = json.loads(clean_json_text(response.text))
                
                if "variants" in variants_data:
                    for j, variant in enumerate(variants_data["variants"]):
                        if j < len(math_indices):
                            original_idx = math_indices[j]
                            # Update the question with the variant
                            questions[original_idx].update({
                                'question': fix_latex_delimiters(variant['question']),
                                'options': [fix_latex_delimiters(opt) for opt in variant['options']],
                                'answer_index': variant['answer_index'],
                                'explanation': fix_latex_delimiters(variant['explanation']),
                                'is_variant': True
                            })
            except Exception as e:
                print(f"Variant Generation Error: {e}")
                # Fallback: keep original questions if generation fails

        return {"questions": questions}
    except Exception as e:
        print(f"Get Review Questions Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class ReviewStatusRequest(BaseModel):
    user_id: str
    mistake_id: str
    is_correct: bool

@app.post("/update_review_status")
async def update_review_status(request: ReviewStatusRequest):
    try:
        doc_ref = db.collection('users').document(request.user_id).collection('mistakes').document(request.mistake_id)
        doc = doc_ref.get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail="Mistake not found")
            
        data = doc.to_dict()
        current_level = data.get('review_level', 0)
        
        if request.is_correct:
            # Level up: 1d -> 3d -> 7d -> 14d -> Done
            intervals = [1, 3, 7, 14, 30]
            next_level = current_level + 1
            
            if next_level >= len(intervals):
                # Mastered! Delete or archive
                doc_ref.delete()
                return {"status": "mastered"}
            else:
                next_review = datetime.now(timezone.utc) + timedelta(days=intervals[next_level])
                doc_ref.update({
                    'review_level': next_level,
                    'next_review_at': next_review
                })
        else:
            # Reset to level 0 (Review tomorrow)
            next_review = datetime.now(timezone.utc) + timedelta(days=1)
            doc_ref.update({
                'review_level': 0,
                'next_review_at': next_review
            })
            
        return {"status": "updated"}
    except Exception as e:
        print(f"Update Review Status Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- AI Lectures ---

class LectureRequest(BaseModel):
    user_id: str
    topic: str
    grade: str = "中学2年生"

@app.post("/generate_lecture")
async def generate_lecture(request: LectureRequest):
    try:
        prompt = f"""
        {request.grade}向けの「{request.topic}」に関する5分間の講義を作成してください。
        スライド（要点）と、先生が話すスクリプト（台本）のセットでお願いします。
        スライドは5〜8枚程度です。
        
        出力フォーマット(JSON):
        {{
            "title": "講義タイトル",
            "slides": [
                {{
                    "title": "スライド1のタイトル",
                    "points": ["要点1", "要点2", "要点3"],
                    "script": "先生が話す内容（親しみやすい口調で）"
                }},
                ...
            ]
        }}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        lecture_data = json.loads(clean_json_text(response.text))
        
        return {"status": "success", "lecture": lecture_data}

    except Exception as e:
        print(f"Generate Lecture Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Long-term Roadmap ---

class RoadmapRequest(BaseModel):
    user_id: str
    goal: str # e.g., "志望校合格", "英検2級"
    current_level: str = "中学2年生平均"
    target_date: str # YYYY-MM-DD

@app.post("/generate_roadmap")
async def generate_roadmap(request: RoadmapRequest):
    try:
        prompt = f"""
        現在のレベル「{request.current_level}」から、目標「{request.goal}」（期限: {request.target_date}）を達成するための長期学習ロードマップを作成してください。
        月ごとのマイルストーンと、具体的な学習内容を提示してください。
        
        出力フォーマット(JSON):
        {{
            "goal": "目標名",
            "months": [
                {{
                    "month": "2024年12月",
                    "theme": "基礎固め",
                    "tasks": ["数学: 一次関数の復習", "英語: 単語帳1周目"]
                }},
                ...
            ]
        }}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        roadmap_data = json.loads(clean_json_text(response.text))
        
        return {"status": "success", "roadmap": roadmap_data}

    except Exception as e:
        print(f"Generate Roadmap Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Voice Tutor ---

@app.post("/voice_chat")
async def voice_chat(file: UploadFile = File(...)):
    try:
        content = await file.read()
        
        # Use a model optimized for speed and audio understanding
        # Using gemini-2.5-flash as requested
        
        prompt = """
        You are a friendly English tutor. 
        The user is practicing English conversation.
        Listen to the user's audio and reply in English.
        Keep your response concise (1-2 sentences) and encouraging.
        If the user makes a grammar mistake, gently correct it in a separate sentence.
        
        Output format (JSON):
        {
            "reply": "Your reply in English",
            "correction": "Correction if needed, otherwise null"
        }
        """
        
        response = model.generate_content([
            {'mime_type': 'audio/mp3', 'data': content}, # Assuming MP3 or WAV, Gemini handles common formats
            prompt
        ], generation_config={"response_mime_type": "application/json"})
        
        result = json.loads(clean_json_text(response.text))
        return result

    except Exception as e:
        print(f"Voice Chat Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Parent Connect ---

class ParentReportRequest(BaseModel):
    user_id: str
    period: str = "weekly" # weekly, daily

@app.post("/generate_parent_report")
async def generate_parent_report(request: ParentReportRequest):
    try:
        # 1. Fetch study logs (Mocking data fetching for now, ideally query Firestore)
        # In a real app, we would query 'study_logs' collection for the last 7 days.
        # Let's assume some dummy stats for the prompt if we can't easily aggregate right now.
        # Or better, let's fetch the analytics data we already have logic for.
        
        # Re-using analytics logic (simplified)
        end_date = datetime.now(timezone.utc)
        start_date = end_date - timedelta(days=7)
        
        docs = db.collection('users').document(request.user_id).collection('study_logs').stream()
            
        total_seconds = 0
        subjects = {}
        
        # Filter in Python to avoid index requirement
        for doc in docs:
            data = doc.to_dict()
            # Check if timestamp is within last 7 days
            timestamp = data.get('timestamp')
            if timestamp:
                # Handle Firestore timestamp or datetime string
                if hasattr(timestamp, 'timestamp'): # Datetime object
                    if timestamp < start_date:
                        continue
                # If string, might need parsing, but for now assume datetime object from Firestore
            
            total_seconds += data.get('duration_seconds', 0)
            subj = data.get('subject', 'Unknown')
            subjects[subj] = subjects.get(subj, 0) + 1

        total_hours = total_seconds / 3600
        top_subject = max(subjects, key=subjects.get) if subjects else "なし"
        
        prompt = f"""
        保護者向けの「学習報告レポート」を作成してください。
        
        【学習データ (過去1週間)】
        - 総学習時間: {total_hours:.1f}時間
        - 取り組んだ科目: {', '.join(subjects.keys())}
        - 最も頑張った科目: {top_subject}
        
        【指示】
        - 親御さんが安心し、子供を褒めたくなるような、温かいトーンで書いてください。
        - LINEやメールで送るのに適した長さ（200文字程度）にしてください。
        - 具体的な数字（時間など）を含めてください。
        
        出力フォーマット(JSON):
        {{
            "message": "こんにちは！今週の〇〇さんの頑張りをお伝えします。..."
        }}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        report_data = json.loads(clean_json_text(response.text))
        
        return {"status": "success", "report": report_data}

    except Exception as e:
        print(f"Generate Parent Report Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Essay Correction ---

@app.post("/correct_essay")
async def correct_essay(
    text: str = Form(None),
    image: UploadFile = File(None)
):
    try:
        if not text and not image:
            raise HTTPException(status_code=400, detail="Either text or image must be provided")

        content_parts = []
        if image:
            img_content = await image.read()
            content_parts.append({'mime_type': image.content_type, 'data': img_content})
        if text:
            content_parts.append(text)

        prompt = """
        あなたはプロの添削講師です。
        ユーザーから提出された文章（テキストまたは画像）を添削してください。
        対象は「英語の作文」または「小論文（日本語）」です。言語を自動判定してください。

        以下の点に注意してフィードバックを行ってください：
        1. **文法・語彙の訂正**: 間違いを指摘し、正しい形を提示。
        2. **より良い表現の提案**: 自然な言い回しや、より高度な語彙の提案。
        3. **論理構成**: 文章全体の流れや説得力についてのアドバイス。
        4. **総合評価**: S, A, B, C の4段階評価。

        出力フォーマット(JSON):
        {
            "original_text": "読み取った（または入力された）原文",
            "corrected_text": "添削後の全文",
            "feedback": [
                {"point": "文法ミス", "explanation": "..." },
                {"point": "表現の改善", "explanation": "..." }
            ],
            "grade": "A",
            "comment": "全体的なコメント"
        }
        """
        
        content_parts.append(prompt)
        
        response = model.generate_content(content_parts, generation_config={"response_mime_type": "application/json"})
        result = json.loads(clean_json_text(response.text))
        
        return {"status": "success", "result": result}

    except Exception as e:
        print(f"Essay Correction Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Official Texts (Hybrid Cram School) ---

class OfficialTextResponse(BaseModel):
    id: str
    title: str
    subject: str
    chapters: List[dict] # [{"title": "Chapter 1", "content": "Markdown content..."}]

@app.get("/official_texts/{text_id}")
async def get_official_text(text_id: str):
    # Mock data for demonstration - FULLY EXPANDED
    if text_id == "math_v1":
        return {
            "id": "math_v1",
            "title": "中学数学 Vol.1 (基礎編)",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 正負の数",
                    "content": """
# 正負の数

## 1. 正負の数の意味
0より大きい数を**正の数**、0より小さい数を**負の数**といいます。
負の数は、マイナス記号（-）をつけて表します。

- **0** は正の数でも負の数でもありません。
- **自然数** とは、正の整数のことです（1, 2, 3...）。

### 反対の性質を持つ量
- 「東へ3km進む」を $+3km$ とすると、「西へ3km進む」は $-3km$ と表せます。
- 「500円の利益」を $+500$ 円とすると、「500円の損失」は $-500$ 円です。

---

## 2. 絶対値と数直線
**絶対値** とは、数直線上で **0（原点）からの距離** のことです。
記号 $|a|$ で表します。

- $|+3| = 3$
- $|-5| = 5$
- $|0| = 0$

数直線上で、右へ行くほど数は大きくなり、左へ行くほど数は小さくなります。
$-5 < -3 < 0 < +2$

---

## 3. 正負の数の計算（加法・減法）

### 同符号の計算（同じマーク）
絶対値の和に、共通の符号をつけます。
- $(+2) + (+3) = +(2+3) = +5$
- $(-2) + (-3) = -(2+3) = -5$

### 異符号の計算（違うマーク）
絶対値の大きい方から小さい方を引き、絶対値の大きい方の符号をつけます。
- $(-5) + (+3) = -(5-3) = -2$
- $(+5) + (-3) = +(5-3) = +2$
"""
                },
                {
                    "title": "第2章: 文字と式",
                    "content": """
# 文字と式

## 1. 文字式の表し方
数学では、数量の関係を一般的に表すために $x$ や $a$ などの文字を使います。

### 基本ルール
1. **かけ算の記号（×）は省く**
   - $a \\times b = ab$
2. **数字は文字の前に書く**
   - $x \\times 5 = 5x$
3. **1は省略する**
   - $x \\times 1 = x$
   - $y \\times (-1) = -y$
4. **同じ文字の積は累乗を使う**
   - $a \\times a = a^2$

---

## 2. 式の値
文字に数字を**代入**して計算した結果を**式の値**といいます。
- 例: $x = -3$ のとき、$2x + 5$ の値は？
  - $2 \\times (-3) + 5 = -6 + 5 = -1$

---

## 3. 数量の表し方
- **速さ・時間・道のり**: (道のり) = (速さ) $\\times$ (時間)
- **割合**: $a$ 円の $x$ % は $\\frac{x}{100}a$ 円
"""
                },
                {
                    "title": "第3章: 方程式",
                    "content": """
# 一次方程式

## 1. 方程式とは
文字の値によって成り立ったり成り立たなかったりする等式。
成り立たせる文字の値を**解**といいます。

## 2. 等式の性質
天秤のように、両辺に同じ操作をしても等号は成り立ちます。
1. **両辺に同じ数を足しても等しい**
2. **両辺から同じ数を引いても等しい**
3. **両辺に同じ数をかけても等しい**
4. **両辺を同じ数（0以外）で割っても等しい**

### 移項（いこう）
項を符号を変えて他方の辺に移すこと。
$$ 3x + 5 = 14 $$
$$ 3x = 14 - 5 $$
$$ 3x = 9 $$
$$ x = 3 $$
"""
                }
            ]
        }
    
    if text_id == "english_v1":
        return {
            "id": "english_v1",
            "title": "中学英語 Vol.1 (基礎編)",
            "subject": "英語",
            "chapters": [
                {
                    "title": "Unit 1: be動詞 (am, are, is)",
                    "content": """
# be動詞

## 1. be動詞の基本
主語によって使い分けます。「〜です」「〜にいる」という意味です。

| 主語 | be動詞 | 短縮形 |
| :--- | :--- | :--- |
| I | am | I'm |
| You | are | You're |
| He / She / It | is | He's / She's / It's |
| We / They | are | We're / They're |

## 2. 否定文
be動詞の後ろに **not** を置きます。
- I am **not** tired. (私は疲れていません。)
- She is **not** a doctor. (彼女は医者ではありません。)

## 3. 疑問文
be動詞を主語の前に出します。
- **Are you** a student?
  - Yes, I am. / No, I am not.
- **Is this** a pen?
  - Yes, it is. / No, it isn't.
"""
                },
                {
                    "title": "Unit 2: 一般動詞",
                    "content": """
# 一般動詞

## 1. 一般動詞とは
be動詞以外の、動作や状態を表す動詞です。
(play, like, study, run, have, want etc.)

- I **play** baseball.
- They **study** English.

## 2. 三人称単数現在形 (三単現のs)
主語が「I, You以外」で「単数」のとき、動詞に **s** または **es** をつけます。

- He **plays** soccer.
- She **watches** TV. (chで終わる語はes)
- Tom **studies** hard. (子音字+yはiに変えてes)

## 3. 否定文と疑問文 (do/does)
助動詞 **do** または **does** を使います。

- I **don't** know him.
- He **doesn't** like carrots. (動詞は原形に戻る！)
- **Do** you like sports?
- **Does** Ken live in Tokyo?
"""
                },
                {
                    "title": "Unit 3: 代名詞",
                    "content": """
# 代名詞の変化

## 人称代名詞の格変化
「誰が」「誰の」「誰を」「誰のもの」によって形が変わります。

| 主格 (〜は) | 所有格 (〜の) | 目的格 (〜を/に) | 所有代名詞 (〜のもの) |
| :--- | :--- | :--- | :--- |
| **I** | **my** | **me** | **mine** |
| **you** | **your** | **you** | **yours** |
| **he** | **his** | **him** | **his** |
| **she** | **her** | **her** | **hers** |
| **we** | **our** | **us** | **ours** |
| **they** | **their** | **them** | **theirs** |

- This is **my** pen. (所有格)
- Please help **me**. (目的格)
"""
                }
            ]
        }

    # ---------------------------------------------------------
    # NEWLY EXPANDED TEXTBOOKS
    # ---------------------------------------------------------

    if text_id == "eng_grammar":
        return {
            "id": "eng_grammar",
            "title": "中学英語 重要文法まとめ",
            "subject": "英語",
            "chapters": [
                {
                    "title": "第1章: 助動詞 (can, must, will)",
                    "content": """
# 助動詞 (Auxiliary Verbs)

## 1. 助動詞のルール
- 動詞の前に置く。
- **直後の動詞は必ず原形**にする。
- 主語が三人称単数でもsはつけない。

## 2. 主要な助動詞
### can (〜できる)
- I **can** swim fast.
- I **cannot** (can't) speak French.
- **Can** you help me?

### will (〜するつもり・でしょう)
未来を表します。be going to と書き換え可能な場合があります。
- I **will** call you later.
- It **will** rain tomorrow.

### must (〜しなければならない)
義務・必要性を表します。have to と書き換え可能です。
- You **must** study hard.
- You **must not** run here. (禁止: 〜してはいけない)

### should (〜すべきだ)
提案やアドバイスを表します。
- You **should** go to the hospital.
"""
                },
                {
                    "title": "第2章: 接続詞 (and, but, because)",
                    "content": """
# 接続詞

## 1. 等位接続詞 (and, but, or)
語と語、文と文を対等に結びます。
- bread **and** butter
- I like math, **but** I don't like history.
- Which do you like, tea **or** coffee?

## 2. 従位接続詞 (when, if, because, that)
主節（メインの文）に説明を加えます。

### when (〜するとき)
- **When** I came home, my mother was cooking.
- (My mother was cooking **when** I came home.)

### if (もし〜なら)
- **If** it is sunny, let's go picnic.
- (Let's go picnic **if** it is sunny.)

### because (〜なので)
- I was late **because** the bus didn't come.

### that (〜ということ)
- I think **that** he is kind. (thatは省略可能)
"""
                }
            ]
        }
    elif text_id == "science_bio":
        return {
            "id": "science_bio",
            "title": "中学理科 生物",
            "subject": "理科",
            "chapters": [
                {
                    "title": "第1章: 植物の生活と種類",
                    "content": """
# 植物の生活と種類

## 1. 花のつくり
- **被子植物**: 胚珠が子房の中にある植物（アブラナ、エンドウなど）
  - 花弁、がく、おしべ、めしべがある。
- **裸子植物**: 胚珠がむき出しになっている植物（マツ、イチョウ、ソテツなど）
  - 子房がないため、果実もできない。

## 2. 光合成と呼吸
- **光合成**: 二酸化炭素 ＋ 水 ＋ 光エネルギー → デンプン（養分） ＋ 酸素
  - 場所: 葉緑体
  - 条件: 光が必要
- **呼吸**: 酸素を取り入れ、二酸化炭素を出す。
  - 昼も夜も常に行っている。

## 3. 根・茎・葉のつくり
- **道管**: 水や養分が通る管。
- **師管**: 葉で作られた栄養分が通る管。
- **維管束**: 道管と師管の集まり。双子葉類では輪状、単子葉類では散在している。
"""
                },
                {
                    "title": "第2章: 動物の生活と種類",
                    "content": """
# 動物の生活と種類

## 1. 消化と吸収
食物を体内で吸収しやすい形に分解すること。
- **炭水化物** → ブドウ糖（アミラーゼなどで分解）
- **タンパク質** → アミノ酸（ペプシン、トリプシンなどで分解）
- **脂肪** → 脂肪酸とモノグリセリド（リパーゼで分解）

## 2. 血液の循環
- **動脈**: 心臓から送り出される血液が流れる血管。壁が厚く弾力がある。
- **静脈**: 心臓に戻る血液が流れる血管。弁がある。
- **赤血球**: 酸素を運ぶ（ヘモグロビン）。
- **白血球**: 細菌などを殺す。
"""
                }
            ]
        }
    elif text_id == "social_history":
        return {
            "id": "social_history",
            "title": "中学社会 歴史年表",
            "subject": "社会",
            "chapters": [
                {
                    "title": "第1章: 古代〜中世",
                    "content": """
# 歴史年表 (古代〜中世)

## 古代
- **57年**: 倭の奴国の王が金印を授かる
- **239年**: 邪馬台国の卑弥呼が魏に使いを送る
- **645年**: 大化の改新（中大兄皇子らが蘇我氏を倒す）
- **710年**: 平城京遷都（奈良時代）
- **794年**: 平安京遷都（平安時代、泣くよウグイス平安京）

## 中世
- **1192年**: 鎌倉幕府成立（源頼朝、いい国作ろう）
- **1274・1281年**: 元寇（文永の役・弘安の役）
- **1334年**: 建武の新政（後醍醐天皇）
- **1338年**: 室町幕府成立（足利尊氏）
- **1467年**: 応仁の乱（戦国時代の始まり）
"""
                },
                {
                    "title": "第2章: 近世 (江戸時代)",
                    "content": """
# 江戸時代

## 1. 幕藩体制の確立
- **1603年**: 徳川家康が征夷大将軍となる。
- **武家諸法度**: 大名を統制するための法律。
- **参勤交代**: 3代将軍家光が義務化。

## 2. 鎖国と外交
- **1639年**: ポルトガル船の来航禁止、鎖国の完成。
- **四つの口**: 長崎（オランダ・中国）、対馬（朝鮮）、薩摩（琉球）、松前（アイヌ）

## 3. 三大改革
- **享保の改革**: 徳川吉宗（目安箱、公事方御定書）
- **寛政の改革**: 松平定信（旧里帰農令）
- **天保の改革**: 水野忠邦（株仲間の解散）
"""
                }
            ]
        }
    elif text_id == "math_v4":
        return {
            "id": "math_v4",
            "title": "中学数学 Vol.4 (応用・データ)",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 確率",
                    "content": """
# 確率

## 1. 確率の定義
ある事柄の起こりやすさを数で表したもの。
起こりうるすべての場合の数を $N$、ある事柄Aの起こる場合の数を $a$ とすると、事柄Aの確率 $P$ は以下で表される。
$$ P = \\frac{a}{N} $$

## 2. 積の法則・和の法則
- **積の法則**: 独立な2つの事象がともに起こる確率 ($P_A \\times P_B$)
- **和の法則**: 同時には起こらない2つの事象のどちらかが起こる確率 ($P_A + P_B$)

## 3. 余事象
「Aが起こらない」確率。
$$ P(\\bar{A}) = 1 - P(A) $$
「少なくとも1つは〜」という問題でよく使う。
"""
                },
                {
                    "title": "第2章: データの活用",
                    "content": """
# データの活用

## 1. 代表値
- **平均値 (Mean)**: データの総和 $\\div$ データの個数
- **中央値 (Median)**: データを大きさ順に並べたときの中央の値
- **最頻値 (Mode)**: 最も頻繁に現れる値

## 2. 箱ひげ図 (Box Plot)
データの散らばり具合を表す図。
- **第1四分位数**: 下位50%の中央値
- **第2四分位数**: 全体の中央値
- **第3四分位数**: 上位50%の中央値
- **四分位範囲**: 第3四分位数 - 第1四分位数
"""
                }
            ]
        }
    elif text_id == "eng_grammar_v3":
        return {
            "id": "eng_grammar_v3",
            "title": "中学英語 文法まとめ Vol.3",
            "subject": "英語",
            "chapters": [
                {
                    "title": "第1章: 不定詞と動名詞",
                    "content": """
# 不定詞と動名詞

## 1. 不定詞 (to + 動詞の原形)
- **名詞的用法**: 〜すること
  - To study English is fun.
- **形容詞的用法**: 〜するための
  - I have homework to do.
- **副詞的用法**: 〜するために、〜して
  - I got up early to run.
  - I am glad to see you.

## 2. 動名詞 (〜ing)
「〜すること」という意味で、名詞の働きをする。
- I like **swimming**.
- He is good at **cooking**. (前置詞の後は必ず動名詞)

### to不定詞と動名詞の使い分け
- **want, hope, plan** → to不定詞をとる
- **enjoy, finish, stop** → 動名詞をとる
- **like, start, begin** → どちらもOK
"""
                },
                {
                    "title": "第2章: 比較",
                    "content": """
# 比較

## 1. 比較級 (-er)
2つのものを比べるときに使う。
- This pen is **longer than** that one.
- She is **taller than** me.

## 2. 最上級 (the -est)
3つ以上の中で一番〜だというとき。
- Mt. Fuji is **the highest** mountain in Japan.
- He runs **the fastest** in his class.

## 3. 原級 (as ~ as)
同じくらい〜だ。
- This book is **as interesting as** that one.
- He is **not as old as** he looks. (彼は見かけほど年をとっていない)
"""
                }
            ]
        }
    elif text_id == "science_earth":
        return {
            "id": "science_earth",
            "title": "中学理科 地学",
            "subject": "理科",
            "chapters": [
                {
                    "title": "第1章: 天気とその変化",
                    "content": """
# 天気とその変化

## 1. 気象要素
- **気温**: 地上1.5mの高さで測る。
- **湿度**: 空気の湿り気の度合い。乾湿計で測る。
- **気圧**: 空気の重さによる圧力。単位はヘクトパスカル(hPa)。

## 2. 前線と天気の変化
- **寒冷前線**: 寒気が暖気を激しく押し上げる。通過時に**にわか雨**や**雷雨**をもたらし、気温が下がる。
- **温暖前線**: 暖気が寒気の上にはい上がる。通過時に穏やかな雨が長く降り、気温が上がる。

## 3. 日本の天気
- **西高東低**: 冬の気圧配置。北西の季節風が吹き、日本海側は雪、太平洋側は晴れ乾燥する。
"""
                },
                {
                    "title": "第2章: 天体",
                    "content": """
# 天体

## 1. 地球の自転と公転
- **自転**: 地球が地軸を中心に1日1回西から東へ回る。→ 昼夜の変化、星の日周運動。
- **公転**: 地球が太陽の周りを1年で1周する。→ 季節の変化、星の年周運動。

## 2. 太陽系
- **内合**: 金星が地球と太陽の間にあるとき。
- **外合**: 太陽が金星と地球の間にあるとき（見えない）。
"""
                }
            ]
        }
    elif text_id == "social_history_v2":
        return {
            "id": "social_history_v2",
            "title": "中学社会 歴史年表 Vol.2",
            "subject": "社会",
            "chapters": [
                {
                    "title": "第1章: 近世〜近代",
                    "content": """
# 歴史年表 (近世〜近代)

- **1603年**: 徳川家康が征夷大将軍となる（江戸幕府）
- **1635年**: 参勤交代の制度化
- **1853年**: ペリー来航（浦賀）
- **1867年**: 大政奉還（徳川慶喜）
- **1868年**: 明治維新（五箇条の御誓文）
- **1889年**: 大日本帝国憲法発布
- **1894年**: 日清戦争
- **1904年**: 日露戦争
                    """
                }
            ]
        }
    elif text_id == "social_geo_v2":
        return {
            "id": "social_geo_v2",
            "title": "中学社会 日本地理",
            "subject": "社会",
            "chapters": [
                {
                    "title": "第1章: 日本の姿",
                    "content": """
# 日本の姿

## 1. 日本の領域
- **領土**: 北海道、本州、四国、九州と多くの島々。
- **領海**: 海岸線から12海里（約22km）。
- **排他的経済水域 (EEZ)**: 海岸線から200海里（約370km）。

## 2. 日本の地形
- 国土の約4分の3が山地。
- **フォッサマグナ**: 本州の中央部にある大きな溝状の地形。
- 川は短くて急流が多い（扇状地ができやすい）。
                    """
                }
            ]
        }
    elif text_id == "math_v5":
        return {
            "id": "math_v5",
            "title": "中学数学 Vol.5",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 平方根",
                    "content": """
# 平方根

## 1. 平方根の意味
- 2乗すると $a$ になる数を、$a$ の**平方根**といいます。
- 正の数 $a$ の平方根は、正と負の2つあり、$\\sqrt{a}$ と $-\\sqrt{a}$ と表します。

## 2. 根号を含む式の計算
- $\\sqrt{a} \\times \\sqrt{b} = \\sqrt{ab}$
- $\\frac{\\sqrt{a}}{\\sqrt{b}} = \\sqrt{\\frac{a}{b}}$
- $a > 0, b > 0$ のとき、$\\sqrt{a^2 b} = a\\sqrt{b}$
                    """
                },
                {
                    "title": "第2章: 二次方程式",
                    "content": """
# 二次方程式

## 1. 因数分解による解き方
- $AB = 0$ ならば $A=0$ または $B=0$
- 例: $(x-2)(x+3)=0$ → $x=2, -3$

## 2. 解の公式
- 二次方程式 $ax^2 + bx + c = 0$ の解は
  $$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$
                    """
                }
            ]
        }
    elif text_id == "math_v6":
        return {
            "id": "math_v6",
            "title": "中学数学 Vol.6",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 関数 $y=ax^2$",
                    "content": """
# 関数 $y=ax^2$

## 1. $y=ax^2$ のグラフ
- 原点を通る放物線。
- $a > 0$ のとき、上に開く（下に凸）。
- $a < 0$ のとき、下に開く（上に凸）。

## 2. 変化の割合
- $x$ の値が $p$ から $q$ まで増加するときの変化の割合は $a(p+q)$
                    """
                },
                {
                    "title": "第2章: 図形の相似",
                    "content": """
# 図形の相似

## 1. 相似条件
1. 3組の辺の比がすべて等しい。
2. 2組の辺の比とその間の角がそれぞれ等しい。
3. 2組の角がそれぞれ等しい。

## 2. 相似比と面積比・体積比
- 相似比が $m:n$ ならば
  - 面積比は $m^2:n^2$
  - 体積比は $m^3:n^3$
                    """
                },
                {
                    "title": "第3章: 三平方の定理",
                    "content": """
# 三平方の定理

## 1. 定理
- 直角三角形の直角をはさむ2辺の長さを $a, b$、斜辺の長さを $c$ とすると
  $$a^2 + b^2 = c^2$$
                    """
                }
            ]
        }
    elif text_id == "eng_grammar_v4":
        return {
            "id": "eng_grammar_v4",
            "title": "中学英語 文法まとめ Vol.4",
            "subject": "英語",
            "chapters": [
                {
                    "title": "第1章: 受動態",
                    "content": """
# 受動態 (be動詞 + 過去分詞)

## 1. 受動態の意味
- 「〜される」という意味を表す。
- This book **was written** by Soseki. (この本は漱石によって書かれた)

## 2. by 以外の前置詞を使う受動態
- be interested in ~ (〜に興味がある)
- be covered with ~ (〜で覆われている)
- be known to ~ (〜に知られている)
                    """
                },
                {
                    "title": "第2章: 現在完了形",
                    "content": """
# 現在完了形 (have/has + 過去分詞)

## 1. 完了・結果
- 「(ちょうど)〜したところだ」「〜してしまった」
- I **have just finished** my homework.

## 2. 経験
- 「〜したことがある」
- I **have been** to Kyoto twice.

## 3. 継続
- 「(ずっと)〜している」
- I **have lived** here for ten years.
                    """
                }
            ]
        }
    elif text_id == "eng_grammar_v5":
        return {
            "id": "eng_grammar_v5",
            "title": "中学英語 文法まとめ Vol.5",
            "subject": "英語",
            "chapters": [
                {
                    "title": "第1章: 分詞",
                    "content": """
# 分詞

## 1. 現在分詞 (~ing)
- 「〜している...」
- Look at the **running** boy. (走っている少年を見て)
- The girl **playing** tennis is my sister. (テニスをしている少女は私の妹です)

## 2. 過去分詞
- 「〜された...」
- This is a used car. (これは中古車です)
- This is a book **written** in English. (これは英語で書かれた本です)
                    """
                },
                {
                    "title": "第2章: 関係代名詞",
                    "content": """
# 関係代名詞

## 1. 主格 (who, which, that)
- I have a friend **who** lives in London. (私にはロンドンに住んでいる友人がいます)
- This is a bus **which** goes to the station. (これは駅へ行くバスです)

## 2. 目的格 (whom, which, that)
- This is the book **(which)** I bought yesterday. (これは私が昨日買った本です)
                    """
                }
            ]
        }
    elif text_id == "science_physics_v2":
        return {
            "id": "science_physics_v2",
            "title": "中学理科 物理 Vol.2",
            "subject": "理科",
            "chapters": [
                {
                    "title": "第1章: 電流",
                    "content": """
# 電流

## 1. 回路と電流・電圧
- **直列回路**: 電流はどこでも同じ。電圧は各部分の和。
- **並列回路**: 電圧はどこでも同じ。電流は各部分の和。

## 2. オームの法則
- 電圧($V$) = 抵抗($R$) × 電流($I$)
- $V = RI$
                    """
                },
                {
                    "title": "第2章: 電流と磁界",
                    "content": """
# 電流と磁界

## 1. 右ねじの法則
- 電流の向きに右ねじを進めるとき、ねじを回す向きに磁界ができる。

## 2. フレミングの左手の法則
- 電流・磁界・力の向きの関係を表す。
- 親指(力)、人差し指(磁界)、中指(電流)を互いに直角にする。
                    """
                }
            ]
        }
    elif text_id == "science_chem_v2":
        return {
            "id": "science_chem_v2",
            "title": "中学理科 化学 Vol.2",
            "subject": "理科",
            "chapters": [
                {
                    "title": "第1章: 化学変化と原子・分子",
                    "content": """
# 化学変化と原子・分子

## 1. 化学反応式
- 化学変化を化学式を使って表した式。
- 例: $2H_2 + O_2 \\rightarrow 2H_2O$ (水の生成)

## 2. 酸化と還元
- **酸化**: 物質が酸素と結びつくこと。
- **還元**: 酸化物が酸素を奪われること。
                    """
                },
                {
                    "title": "第2章: イオン",
                    "content": """
# イオン

## 1. 電解質と非電解質
- **電解質**: 水に溶かすと電流が流れる物質（食塩、塩化水素など）。
- **非電解質**: 水に溶かしても電流が流れない物質（砂糖、エタノールなど）。

## 2. イオン式
- 水素イオン ($H^+$)
- 塩化物イオン ($Cl^-$)
- ナトリウムイオン ($Na^+$)
                    """
                }
            ]
        }
    elif text_id == "science_bio_v2":
        return {
            "id": "science_bio_v2",
            "title": "中学理科 生物 Vol.2",
            "subject": "理科",
            "chapters": [
                {
                    "title": "第1章: 生命の連続性",
                    "content": """
# 生命の連続性

## 1. 細胞分裂
- 1つの細胞が分かれて2つの細胞になること。
- **体細胞分裂**: 体をつくる細胞の分裂。染色体の数は変わらない。
- **減数分裂**: 生殖細胞を作るときの分裂。染色体の数が半分になる。

## 2. 遺伝
- 親の形質が子に伝わること。
- **メンデルの法則**: 優性の法則、分離の法則。
                    """
                }
            ]
        }
    elif text_id == "science_earth_v2":
        return {
            "id": "science_earth_v2",
            "title": "中学理科 地学 Vol.2",
            "subject": "理科",
            "chapters": [
                {
                    "title": "第1章: 地球と宇宙",
                    "content": """
# 地球と宇宙

## 1. 地球の運動
- **自転**: 地球が地軸を中心に1日1回回転すること（日周運動の原因）。
- **公転**: 地球が太陽の周りを1年で1周すること（年周運動の原因）。

## 2. 太陽系
- **恒星**: 自ら光を出して輝く天体（太陽）。
- **惑星**: 恒星の周りを回る天体（水金地火木土天海）。
                    """
                }
            ]
        }
    elif text_id == "social_history_v3":
        return {
            "id": "social_history_v3",
            "title": "中学社会 歴史年表 Vol.3",
            "subject": "社会",
            "chapters": [
                {
                    "title": "第1章: 現代",
                    "content": """
# 歴史年表 (現代)

- **1914年**: 第一次世界大戦
- **1929年**: 世界恐慌
- **1939年**: 第二次世界大戦
- **1945年**: ポツダム宣言受諾、国際連合設立
- **1964年**: 東京オリンピック
- **1989年**: ベルリンの壁崩壊、冷戦終結
                    """
                }
            ]
        }
    elif text_id == "social_geo_v3":
        return {
            "id": "social_geo_v3",
            "title": "中学社会 世界地理 Vol.2",
            "subject": "社会",
            "chapters": [
                {
                    "title": "第1章: 世界の諸地域",
                    "content": """
# 世界の諸地域

## 1. アジア州
- 世界最大の面積と人口を持つ州。
- 東アジア、東南アジア、南アジア、西アジア、中央アジアに区分される。
- **モンスーン（季節風）**: 夏は海から陸へ、冬は陸から海へ吹く風。

## 2. ヨーロッパ州
- 偏西風と暖流（北大西洋海流）の影響で、高緯度のわりに温暖。
- **EU（欧州連合）**: 経済的・政治的な統合を目指す組織。
                    """
                }
            ]
        }
    elif text_id == "social_civics_v2":
        return {
            "id": "social_civics_v2",
            "title": "中学社会 公民 Vol.2",
            "subject": "社会",
            "chapters": [
                {
                    "title": "第1章: 私たちの生活と経済",
                    "content": """
# 私たちの生活と経済

## 1. 市場経済
- **需要**: 買い手が買おうとする量。
- **供給**: 売り手が売ろうとする量。
- **均衡価格**: 需要量と供給量が一致したときの価格。

## 2. 金融
- 資金の貸し借りのこと。
- **日本銀行**: 日本の中央銀行。「発券銀行」「銀行の銀行」「政府の銀行」の役割を持つ。
                    """
                }
            ]
        }
    elif text_id == "hs_math_1":
        return {
            "id": "hs_math_1",
            "title": "高校数学 I",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 数と式",
                    "content": """
# 数と式

## 1. 実数
- 有理数と無理数を合わせて**実数**という。
- **絶対値**: $|a| = a (a \\geqq 0), -a (a < 0)$

## 2. 因数分解
- $x^2 + (a+b)x + ab = (x+a)(x+b)$
- $a^3 + b^3 = (a+b)(a^2 - ab + b^2)$
- $a^3 - b^3 = (a-b)(a^2 + ab + b^2)$
                    """
                },
                {
                    "title": "第2章: 三角比",
                    "content": """
# 三角比

## 1. 定義
直角三角形において
- $\\sin \\theta = \\frac{\\text{対辺}}{\\text{斜辺}}$
- $\\cos \\theta = \\frac{\\text{底辺}}{\\text{斜辺}}$
- $\\tan \\theta = \\frac{\\text{対辺}}{\\text{底辺}}$

## 2. 相互関係
- $\\tan \\theta = \\frac{\\sin \\theta}{\\cos \\theta}$
- $\\sin^2 \\theta + \\cos^2 \\theta = 1$
                    """
                }
            ]
        }
    elif text_id == "hs_math_a":
        return {
            "id": "hs_math_a",
            "title": "高校数学 A",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 場合の数と確率",
                    "content": """
# 場合の数と確率

## 1. 順列と組合せ
- **順列**: $n$個から$r$個とって並べる $_nP_r = \\frac{n!}{(n-r)!}$
- **組合せ**: $n$個から$r$個とる $_nC_r = \\frac{_nP_r}{r!} = \\frac{n!}{r!(n-r)!}$

## 2. 条件付き確率
- 事象Aが起こったときに事象Bが起こる確率
  $$P_A(B) = \\frac{P(A \\cap B)}{P(A)}$$
                    """
                }
            ]
        }
    elif text_id == "hs_math_2":
        return {
            "id": "hs_math_2",
            "title": "高校数学 II",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 三角関数",
                    "content": """
# 三角関数

## 1. 弧度法
- 半径$r$、弧の長さ$r$の扇形の中心角を**1ラジアン**とする。
- $180^\\circ = \\pi$ ラジアン

## 2. 加法定理
- $\\sin(\\alpha + \\beta) = \\sin\\alpha\\cos\\beta + \\cos\\alpha\\sin\\beta$
- $\\cos(\\alpha + \\beta) = \\cos\\alpha\\cos\\beta - \\sin\\alpha\\sin\\beta$
                    """
                },
                {
                    "title": "第2章: 微分・積分",
                    "content": """
# 微分・積分

## 1. 導関数
- $f'(x) = \\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}$
- $(x^n)' = nx^{n-1}$

## 2. 定積分
- $\\int_a^b f(x) dx = [F(x)]_a^b = F(b) - F(a)$
                    """
                }
            ]
        }
    elif text_id == "hs_math_b":
        return {
            "id": "hs_math_b",
            "title": "高校数学 B",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 数列",
                    "content": """
# 数列

## 1. 等差数列
- 一般項: $a_n = a + (n-1)d$
- 和: $S_n = \\frac{1}{2}n(a+l)$

## 2. 等比数列
- 一般項: $a_n = ar^{n-1}$
- 和: $S_n = \\frac{a(1-r^n)}{1-r}$ ($r \\neq 1$)
                    """
                }
            ]
        }
    elif text_id == "hs_math_3":
        return {
            "id": "hs_math_3",
            "title": "高校数学 III",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 極限",
                    "content": """
# 極限

## 1. 数列の極限
- $\\lim_{n \\to \\infty} \\frac{1}{n} = 0$
- 無限等比級数の和: $\\frac{a}{1-r}$ ($|r| < 1$)

## 2. 関数の極限
- $\\lim_{x \\to 0} \\frac{\\sin x}{x} = 1$
                    """
                }
            ]
        }
    elif text_id == "hs_math_c":
        return {
            "id": "hs_math_c",
            "title": "高校数学 C",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: ベクトル",
                    "content": """
# ベクトル

## 1. ベクトルの演算
- 和: $\\vec{a} + \\vec{b}$
- 差: $\\vec{a} - \\vec{b}$
- 実数倍: $k\\vec{a}$

## 2. 内積
- $\\vec{a} \\cdot \\vec{b} = |\\vec{a}| |\\vec{b}| \\cos \\theta$
- 成分表示: $\\vec{a} \\cdot \\vec{b} = a_1 b_1 + a_2 b_2$
                    """
                }
            ]
        }
    elif text_id == "hs_eng_grammar":
        return {
            "id": "hs_eng_grammar",
            "title": "高校英語 総合文法",
            "subject": "英語(高校)",
            "chapters": [
                {
                    "title": "第1章: 仮定法",
                    "content": """
# 仮定法

## 1. 仮定法過去
- 現在の事実と反対のことを仮定する。
- If I **were** a bird, I **could** fly to you. (もし私が鳥なら、あなたのところへ飛んでいけるのに)

## 2. 仮定法過去完了
- 過去の事実と反対のことを仮定する。
- If I **had known** the truth, I **would have told** you. (もし真実を知っていたら、あなたに話していただろう)
                    """
                },
                {
                    "title": "第2章: 関係詞",
                    "content": """
# 関係詞

## 1. 関係副詞 (where, when, why, how)
- This is the place **where** I was born. (ここは私が生まれた場所です)

## 2. 複合関係詞 (whoever, whatever, etc.)
- **Whoever** comes is welcome. (来る人は誰でも歓迎します)
                    """
                }
            ]
        }
    elif text_id == "hs_eng_reading":
        return {
            "id": "hs_eng_reading",
            "title": "高校英語 長文読解",
            "subject": "英語(高校)",
            "chapters": [
                {
                    "title": "第1章: 論説文",
                    "content": """
# 論説文の読み方

## 1. パラグラフ・リーディング
- 1つのパラグラフには1つのトピックがある。
- トピック・センテンス（主題文）を見つけることが重要。

## 2. ディスコース・マーカー
- **逆接**: However, But, Although
- **例示**: For example, For instance
- **結論**: Therefore, Thus, In conclusion
                    """
                }
            ]
        }
    elif text_id == "hs_eng_vocab":
        return {
            "id": "hs_eng_vocab",
            "title": "高校英単語 ターゲット1900",
            "subject": "英語(高校)",
            "chapters": [
                {
                    "title": "Section 1: 常に試験に出る基本単語",
                    "content": """
# 基本単語 1-100

1. **create**: 創造する
2. **increase**: 増加する
3. **improve**: 向上させる
4. **mean**: 意味する、意図する
5. **own**: 所有する
6. **include**: 含む
7. **consider**: 見なす、よく考える
8. **allow**: 許す
9. **suggest**: 提案する
10. **produce**: 生産する
                    """
                }
            ]
        }
    elif text_id == "hs_science_physics":
        return {
            "id": "hs_science_physics",
            "title": "高校物理",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 力学",
                    "content": """
# 力学

## 1. 等加速度直線運動
- $v = v_0 + at$
- $x = v_0 t + \\frac{1}{2}at^2$
- $v^2 - v_0^2 = 2ax$

## 2. 運動方程式
- $ma = F$
  - $m$: 質量
  - $a$: 加速度
  - $F$: 力
                    """
                },
                {
                    "title": "第2章: 波動",
                    "content": """
# 波動

## 1. 波の性質
- $v = f \\lambda$
  - $v$: 波の速さ
  - $f$: 振動数
  - $\\lambda$: 波長

## 2. ドップラー効果
- 音源が動くとき、観測される振動数が変化する現象。
- 近づくときは高く、遠ざかるときは低く聞こえる。
                    """
                }
            ]
        }
    elif text_id == "hs_science_chem":
        return {
            "id": "hs_science_chem",
            "title": "高校化学",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 物質の構成",
                    "content": """
# 物質の構成

## 1. 原子構造
- 原子核（陽子＋中性子）と電子からなる。
- **同位体**: 原子番号（陽子数）は同じだが、質量数（中性子数）が異なる原子。

## 2. 化学結合
- **イオン結合**: 陽イオンと陰イオンの静電気力による結合。
- **共有結合**: 電子対を共有することによる結合。
- **金属結合**: 自由電子による金属原子間の結合。
                    """
                },
                {
                    "title": "第2章: 物質の変化",
                    "content": """
# 物質の変化

## 1. 酸と塩基
- **アレニウスの定義**: 水溶液中で $H^+$ を生じるのが酸、$OH^-$ を生じるのが塩基。
- **ブレンステッドの定義**: $H^+$ を与えるのが酸、$H^+$ を受け取るのが塩基。

## 2. 酸化還元反応
- 電子 $e^-$ を失うのが酸化、受け取るのが還元。
                    """
                }
            ]
        }
    elif text_id == "hs_science_bio":
        return {
            "id": "hs_science_bio",
            "title": "高校生物",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 細胞と分子",
                    "content": """
# 細胞と分子

## 1. 細胞小器官
- **ミトコンドリア**: 呼吸の場。ATPを合成する。
- **葉緑体**: 光合成の場。
- **リボソーム**: タンパク質合成の場。

## 2. DNAの構造
- 二重らせん構造。
- 塩基の相補性: A(アデニン)とT(チミン)、G(グアニン)とC(シトシン)が結合する。
                    """
                }
            ]
        }
    elif text_id == "hs_science_earth":
        return {
            "id": "hs_science_earth",
            "title": "高校地学",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 地球の概観",
                    "content": """
# 地球の概観

## 1. 地球の形と大きさ
- 地球は回転楕円体である。
- 赤道半径は約6378km、極半径は約6357km。

## 2. プレートテクトニクス
- 地球の表面は十数枚のプレートで覆われている。
- プレートの境界で地震や火山活動が活発。
                    """
                }
            ]
        }
    elif text_id == "hs_social_world_history":
        return {
            "id": "hs_social_world_history",
            "title": "高校世界史",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 市民革命と産業革命",
                    "content": """
# 市民革命と産業革命

## 1. アメリカ独立革命
- 1776年: アメリカ独立宣言。
- ワシントンが初代大統領に就任。

## 2. フランス革命
- 1789年: バスティーユ牢獄襲撃。
- 人権宣言: 「人は生まれながらにして自由かつ平等である」

## 3. 産業革命
- 18世紀後半、イギリスで始まる。
- 蒸気機関の発明（ワット）により、工場制機械工業が発展。
                    """
                }
            ]
        }
    elif text_id == "hs_social_japan_history":
        return {
            "id": "hs_social_japan_history",
            "title": "高校日本史",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 幕藩体制の確立",
                    "content": """
# 幕藩体制の確立

## 1. 江戸幕府の成立
- 1603年: 徳川家康が征夷大将軍に就任。
- 幕藩体制: 幕府（将軍）と藩（大名）が土地と人民を統治する仕組み。

## 2. 鎖国政策
- キリスト教の禁止と貿易の統制。
- 1639年: ポルトガル船の来航禁止（鎖国の完成）。
- オランダ、中国（清）、朝鮮、琉球とのみ交流。
                    """
                }
            ]
        }
    elif text_id == "hs_social_geography":
        return {
            "id": "hs_social_geography",
            "title": "高校地理",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 地図と地理情報",
                    "content": """
# 地図と地理情報

## 1. 地図の投影法
- **メルカトル図法**: 角度が正しい（正角図法）。航海図に利用。
- **正距方位図法**: 中心からの距離と方位が正しい。航空図に利用。
- **モルワイデ図法**: 面積が正しい（正積図法）。分布図に利用。

## 2. GIS（地理情報システム）
- コンピュータを使って地理情報を収集・分析・表示するシステム。
                    """
                }
            ]
        }
    elif text_id == "hs_social_civics":
        return {
            "id": "hs_social_civics",
            "title": "高校公民（倫理・政経）",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 青年期と自己形成",
                    "content": """
# 青年期と自己形成

## 1. 青年期の特徴
- **マージナル・マン（境界人）**: 子供から大人への過渡期にある人（レヴィン）。
- **心理的離乳**: 親からの精神的な自立（ホリングワース）。
- **アイデンティティ（自我同一性）の確立**: 「自分は何者か」という確信を持つこと（エリクソン）。

## 2. 現代の経済社会
- **資本主義経済**: 私有財産制、市場経済、自由競争を特徴とする。
- **アダム・スミス**: 『国富論』で「見えざる手」を説いた。
                    """
                }
            ]
        }
    elif text_id == "hs_math_2_advanced":
        return {
            "id": "hs_math_2_advanced",
            "title": "高校数学 II 発展",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 指数関数・対数関数",
                    "content": """
# 指数関数・対数関数

## 1. 指数関数
- $y = a^x$ ($a > 0, a \\neq 1$)
- $a > 1$ のとき単調増加、$0 < a < 1$ のとき単調減少

## 2. 対数関数
- $y = \\log_a x$ ($a > 0, a \\neq 1, x > 0$)
- 指数関数の逆関数

## 3. 対数の性質
- $\\log_a MN = \\log_a M + \\log_a N$
- $\\log_a \\frac{M}{N} = \\log_a M - \\log_a N$
- $\\log_a M^k = k \\log_a M$
                    """
                }
            ]
        }
    elif text_id == "hs_math_3_advanced":
        return {
            "id": "hs_math_3_advanced",
            "title": "高校数学 III 発展",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 複素数平面",
                    "content": """
# 複素数平面

## 1. 複素数の極形式
- $z = r(\\cos \\theta + i \\sin \\theta) = re^{i\\theta}$
- $r$: 絶対値、$\\theta$: 偏角

## 2. ド・モアブルの定理
- $(\\cos \\theta + i \\sin \\theta)^n = \\cos n\\theta + i \\sin n\\theta$
                    """
                }
            ]
        }
    elif text_id == "hs_science_physics_v2":
        return {
            "id": "hs_science_physics_v2",
            "title": "高校物理 Vol.2",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 電磁気学",
                    "content": """
# 電磁気学

## 1. クーロンの法則
- 2つの点電荷間に働く力
  $$F = k\\frac{q_1 q_2}{r^2}$$

## 2. 電場と電位
- 電場 $E = \\frac{F}{q}$
- 電位 $V$: 単位正電荷が持つ位置エネルギー
                    """
                },
                {
                    "title": "第2章: 電磁誘導",
                    "content": """
# 電磁誘導

## 1. ファラデーの電磁誘導の法則
- 磁束の変化により起電力が生じる
  $$V = -\\frac{d\\Phi}{dt}$$

## 2. レンツの法則
- 誘導電流は、磁束の変化を妨げる向きに流れる
                    """
                }
            ]
        }
    elif text_id == "hs_science_physics_v3":
        return {
            "id": "hs_science_physics_v3",
            "title": "高校物理 Vol.3",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 熱力学",
                    "content": """
# 熱力学

## 1. 熱力学第一法則
- エネルギー保存の法則
  $$\\Delta U = Q - W$$
  - $\\Delta U$: 内部エネルギーの変化
  - $Q$: 加えた熱量
  - $W$: 気体がした仕事

## 2. 理想気体の状態方程式
- $PV = nRT$
                    """
                }
            ]
        }
    elif text_id == "hs_science_physics_v4":
        return {
            "id": "hs_science_physics_v4",
            "title": "高校物理 Vol.4",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 原子物理",
                    "content": """
# 原子物理

## 1. 光の粒子性
- **光電効果**: 光が金属に当たると電子が飛び出す現象
- アインシュタインの光量子仮説: $E = hf$

## 2. 原子の構造
- **ボーアの原子模型**: 電子は特定の軌道のみを回る
- エネルギー準位: $E_n = -\\frac{13.6}{n^2}$ eV
                    """
                }
            ]
        }
    elif text_id == "hs_science_chem_v3":
        return {
            "id": "hs_science_chem_v3",
            "title": "高校化学 Vol.3",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 有機化学",
                    "content": """
# 有機化学

## 1. 炭化水素
- **アルカン**: $C_nH_{2n+2}$ (単結合のみ)
- **アルケン**: $C_nH_{2n}$ (二重結合を含む)
- **アルキン**: $C_nH_{2n-2}$ (三重結合を含む)

## 2. 官能基
- **ヒドロキシ基** (-OH): アルコール
- **カルボキシ基** (-COOH): カルボン酸
- **アミノ基** (-NH₂): アミン
                    """
                }
            ]
        }
    elif text_id == "hs_science_chem_v4":
        return {
            "id": "hs_science_chem_v4",
            "title": "高校化学 Vol.4",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 無機化学",
                    "content": """
# 無機化学

## 1. 典型元素
- **アルカリ金属** (1族): Li, Na, K など
  - 水と激しく反応し、水素を発生
- **ハロゲン** (17族): F, Cl, Br, I
  - 酸化力が強い

## 2. 遷移元素
- **鉄** (Fe): 赤血球のヘモグロビンに含まれる
- **銅** (Cu): 電気伝導性が高い
                    """
                }
            ]
        }
    elif text_id == "hs_science_bio_v2":
        return {
            "id": "hs_science_bio_v2",
            "title": "高校生物 Vol.2",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 遺伝",
                    "content": """
# 遺伝

## 1. メンデルの法則
- **優性の法則**: 対立形質のうち一方が現れる
- **分離の法則**: 配偶子形成時に対立遺伝子が分離する
- **独立の法則**: 異なる形質の遺伝子は独立に分配される

## 2. 遺伝子と染色体
- 遺伝子は染色体上に存在する
- **連鎖**: 同じ染色体上の遺伝子は一緒に遺伝しやすい
                    """
                }
            ]
        }
    elif text_id == "hs_science_bio_v3":
        return {
            "id": "hs_science_bio_v3",
            "title": "高校生物 Vol.3",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 進化",
                    "content": """
# 進化

## 1. ダーウィンの進化論
- **自然選択説**: 環境に適応した個体が生き残り、子孫を残す

## 2. 進化の証拠
- **相同器官**: 起源は同じだが、機能が異なる器官（例：ヒトの腕とコウモリの翼）
- **痕跡器官**: 退化して機能を失った器官（例：ヒトの尾骨）
                    """
                }
            ]
        }
    elif text_id == "hs_science_bio_v4":
        return {
            "id": "hs_science_bio_v4",
            "title": "高校生物 Vol.4",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 生態系",
                    "content": """
# 生態系

## 1. 生態系の構成
- **生産者**: 光合成を行う植物
- **消費者**: 他の生物を食べる動物
- **分解者**: 有機物を無機物に分解する菌類・細菌類

## 2. 物質循環
- **炭素循環**: 光合成と呼吸による二酸化炭素の循環
- **窒素循環**: 窒素固定、硝化、脱窒による窒素の循環
                    """
                }
            ]
        }
    # Junior High Math additions
    elif text_id == "math_v7":
        return {
            "id": "math_v7",
            "title": "中学数学 Vol.7",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 連立方程式",
                    "content": """
# 連立方程式

## 1. 連立方程式とは
- 2つ以上の方程式を同時に満たす解を求める問題

## 2. 解き方
- **加減法**: 一方の文字を消去する
  - 例: $x + y = 5$, $x - y = 1$ → 辺々を足して $2x = 6$, $x = 3$
- **代入法**: 一方の式を他方に代入する
                    """
                }
            ]
        }
    elif text_id == "math_v8":
        return {
            "id": "math_v8",
            "title": "中学数学 Vol.8",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 一次関数",
                    "content": """
# 一次関数

## 1. 一次関数の式
- $y = ax + b$ ($a, b$は定数、$a \\neq 0$)
- $a$: 傾き、$b$: 切片

## 2. グラフ
- 直線になる
- 傾き$a$が正のとき右上がり、負のとき右下がり
- 2点$(x_1, y_1)$, $(x_2, y_2)$を通る直線の傾き: $a = \\frac{y_2 - y_1}{x_2 - x_1}$
                    """
                }
            ]
        }
    elif text_id == "math_v9":
        return {
            "id": "math_v9",
            "title": "中学数学 Vol.9",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 図形の証明",
                    "content": """
# 図形の証明

## 1. 三角形の合同条件
1. 3組の辺がそれぞれ等しい
2. 2組の辺とその間の角がそれぞれ等しい
3. 1組の辺とその両端の角がそれぞれ等しい

## 2. 証明の書き方
- 仮定と結論を明確にする
- 根拠を示しながら論理的に進める
                    """
                }
            ]
        }
    # Junior High English additions
    elif text_id == "eng_grammar_v6":
        return {
            "id": "eng_grammar_v6",
            "title": "中学英語 文法まとめ Vol.6",
            "subject": "英語",
            "chapters": [
                {
                    "title": "第1章: 助動詞",
                    "content": """
# 助動詞

## 1. can
- 「〜できる」（能力）: I **can** swim.
- 「〜してもよい」（許可）: You **can** use my pen.

## 2. must / have to
- **must**: 「〜しなければならない」（義務・強制）
- **have to**: 「〜しなければならない」（客観的必要性）
- **must not**: 「〜してはいけない」（禁止）
- **don't have to**: 「〜する必要はない」（不必要）

## 3. should
- 「〜すべきだ」（助言）: You **should** study hard.
                    """
                }
            ]
        }
    elif text_id == "eng_grammar_v7":
        return {
            "id": "eng_grammar_v7",
            "title": "中学英語 文法まとめ Vol.7",
            "subject": "英語",
            "chapters": [
                {
                    "title": "第1章: 疑問詞",
                    "content": """
# 疑問詞

## 1. 基本の疑問詞
- **What**: 何（What is this?）
- **Who**: 誰（Who is he?）
- **When**: いつ（When did you come?）
- **Where**: どこ（Where do you live?）
- **Why**: なぜ（Why are you sad?）
- **How**: どのように（How do you go to school?）

## 2. How を使った表現
- **How old**: 何歳
- **How many**: いくつ（数）
- **How much**: いくら（値段）、どのくらい（量）
                    """
                }
            ]
        }
    elif text_id == "eng_grammar_v8":
        return {
            "id": "eng_grammar_v8",
            "title": "中学英語 文法まとめ Vol.8",
            "subject": "英語",
            "chapters": [
                {
                    "title": "第1章: 接続詞",
                    "content": """
# 接続詞

## 1. 等位接続詞
- **and**: そして（I like cats **and** dogs.）
- **but**: しかし（I'm tired, **but** I'm happy.）
- **or**: または（Tea **or** coffee?）

## 2. 従属接続詞
- **when**: 〜とき（**When** I was young, I lived in Tokyo.）
- **if**: もし〜なら（**If** it rains, I will stay home.）
- **because**: なぜなら（I'm happy **because** I passed the test.）
- **that**: 〜ということ（I think **that** he is kind.）
                    """
                }
            ]
        }
    # High School Science additions
    elif text_id == "hs_science_chem_v2":
        return {
            "id": "hs_science_chem_v2",
            "title": "高校化学 Vol.2",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 化学平衡",
                    "content": """
# 化学平衡

## 1. 可逆反応と化学平衡
- **可逆反応**: 正反応と逆反応が同時に起こる反応
- **化学平衡**: 正反応と逆反応の速度が等しくなった状態

## 2. 平衡定数
- $aA + bB \\rightleftharpoons cC + dD$ のとき
  $$K = \\frac{[C]^c[D]^d}{[A]^a[B]^b}$$

## 3. ルシャトリエの原理
- 平衡状態にある系に変化を加えると、その変化を打ち消す方向に平衡が移動する
                    """
                },
                {
                    "title": "第2章: 反応速度",
                    "content": """
# 反応速度

## 1. 反応速度に影響する因子
- **濃度**: 濃度が高いほど速い
- **温度**: 温度が高いほど速い
- **触媒**: 反応速度を速める物質

## 2. 活性化エネルギー
- 反応が起こるために必要な最小のエネルギー
                    """
                }
            ]
        }
    elif text_id == "hs_science_earth_v2":
        return {
            "id": "hs_science_earth_v2",
            "title": "高校地学 Vol.2",
            "subject": "理科(高校)",
            "chapters": [
                {
                    "title": "第1章: 気象",
                    "content": """
# 気象

## 1. 大気の構造
- **対流圏**: 地表から約11km。天気現象が起こる層。
- **成層圏**: 約11〜50km。オゾン層がある。

## 2. 日本の天気
- **梅雨**: 6〜7月。オホーツク海高気圧と太平洋高気圧の間に停滞前線。
- **台風**: 熱帯低気圧が発達したもの。中心付近の最大風速が17.2m/s以上。
                    """
                },
                {
                    "title": "第2章: 海洋",
                    "content": """
# 海洋

## 1. 海流
- **暖流**: 低緯度から高緯度へ流れる（黒潮、対馬海流）
- **寒流**: 高緯度から低緯度へ流れる（親潮、リマン海流）

## 2. 海水の性質
- 塩分濃度: 平均約3.5%
- 深層水: 冷たく、酸素が豊富
                    """
                }
            ]
        }
    # High School World History additions
    elif text_id == "hs_social_world_history_v2":
        return {
            "id": "hs_social_world_history_v2",
            "title": "高校世界史 Vol.2",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 古代文明",
                    "content": """
# 古代文明

## 1. メソポタミア文明
- チグリス川・ユーフラテス川流域
- **楔形文字**: シュメール人が発明
- **ハンムラビ法典**: 「目には目を、歯には歯を」

## 2. エジプト文明
- ナイル川流域
- **ピラミッド**: ファラオ（王）の墓
- **象形文字（ヒエログリフ）**: 神聖文字
                    """
                }
            ]
        }
    elif text_id == "hs_social_world_history_v3":
        return {
            "id": "hs_social_world_history_v3",
            "title": "高校世界史 Vol.3",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 中世ヨーロッパ",
                    "content": """
# 中世ヨーロッパ

## 1. 封建制度
- 主君と家臣の土地を媒介とした主従関係
- **荘園**: 領主が支配する自給自足の経済単位

## 2. キリスト教会の権威
- **ローマ教皇**: キリスト教世界の最高権威
- **十字軍**: イスラム教徒からエルサレムを奪還する遠征（1096〜1270年）
                    """
                }
            ]
        }
    elif text_id == "hs_social_world_history_v4":
        return {
            "id": "hs_social_world_history_v4",
            "title": "高校世界史 Vol.4",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 近現代史",
                    "content": """
# 近現代史

## 1. 第一次世界大戦（1914-1918）
- **サラエボ事件**: オーストリア皇太子暗殺が引き金
- **三国同盟** vs **三国協商**
- **ベルサイユ条約**: ドイツに厳しい賠償

## 2. 第二次世界大戦（1939-1945）
- ヒトラーのポーランド侵攻で開戦
- **連合国**（米英仏ソ）vs **枢軸国**（独伊日）
- 1945年: ドイツ降伏、日本降伏（原爆投下）
                    """
                }
            ]
        }
    # High School Japanese History additions
    elif text_id == "hs_social_japan_history_v2":
        return {
            "id": "hs_social_japan_history_v2",
            "title": "高校日本史 Vol.2",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 古代〜平安時代",
                    "content": """
# 古代〜平安時代

## 1. 飛鳥時代
- **聖徳太子**: 十七条憲法、遣隋使の派遣
- **大化の改新**（645年）: 中大兄皇子と中臣鎌足が蘇我氏を倒す

## 2. 奈良時代
- **平城京**: 710年遷都
- **律令制**: 中国にならった法律と税制

## 3. 平安時代
- **平安京**: 794年遷都（桓武天皇）
- **摂関政治**: 藤原氏が摂政・関白として権力を握る
- **院政**: 上皇が政治の実権を握る
                    """
                }
            ]
        }
    elif text_id == "hs_social_japan_history_v3":
        return {
            "id": "hs_social_japan_history_v3",
            "title": "高校日本史 Vol.3",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 鎌倉〜室町時代",
                    "content": """
# 鎌倉〜室町時代

## 1. 鎌倉幕府
- **源頼朝**: 1192年征夷大将軍に就任
- **執権政治**: 北条氏が実権を握る
- **元寇**: 1274年（文永の役）、1281年（弘安の役）

## 2. 室町幕府
- **足利尊氏**: 1338年征夷大将軍に就任
- **南北朝の動乱**: 南朝（後醍醐天皇）と北朝（足利氏）の対立
- **応仁の乱**（1467年）: 戦国時代の始まり
                    """
                }
            ]
        }
    elif text_id == "hs_social_japan_history_v4":
        return {
            "id": "hs_social_japan_history_v4",
            "title": "高校日本史 Vol.4",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 明治以降",
                    "content": """
# 明治以降

## 1. 明治維新
- **五箇条の御誓文**（1868年）: 新政府の基本方針
- **廃藩置県**（1871年）: 藩を廃止し、府県を設置
- **文明開化**: 西洋文化の導入

## 2. 大正デモクラシー
- **普通選挙法**（1925年）: 25歳以上の男子に選挙権
- **治安維持法**（1925年）: 社会主義運動の取り締まり

## 3. 昭和
- **太平洋戦争**（1941-1945）
- **日本国憲法**（1946年公布、1947年施行）
                    """
                }
            ]
        }
    # High School Geography addition
    elif text_id == "hs_social_geography_v2":
        return {
            "id": "hs_social_geography_v2",
            "title": "高校地理 Vol.2",
            "subject": "社会(高校)",
            "chapters": [
                {
                    "title": "第1章: 系統地理",
                    "content": """
# 系統地理

## 1. 気候
- **熱帯**: 年中高温（熱帯雨林気候、サバナ気候）
- **乾燥帯**: 降水量が少ない（砂漠気候、ステップ気候）
- **温帯**: 四季の変化（温暖湿潤気候、地中海性気候、西岸海洋性気候）
- **冷帯**: 冬が長く寒い（亜寒帯気候）
- **寒帯**: 年中寒い（ツンドラ気候、氷雪気候）

## 2. 地形
- **造山帯**: 新期造山帯（環太平洋、アルプス・ヒマラヤ）、古期造山帯
- **平野**: 沖積平野、洪積台地

## 3. 産業
- **農業**: 自給的農業、商業的農業
- **工業**: 先進国の工業、新興工業国（NIEs）
                    """
                }
            ]
        }
    # Junior High Japanese
    elif text_id == "japanese_modern_v1":
        return {
            "id": "japanese_modern_v1",
            "title": "中学国語 現代文 Vol.1",
            "subject": "国語",
            "chapters": [
                {
                    "title": "第1章: 説明文の読解",
                    "content": """
# 説明文の読解

## 1. 文章構成
- **序論**: 問題提起、話題の提示
- **本論**: 具体例、理由、根拠
- **結論**: まとめ、筆者の主張

## 2. 読解のポイント
- **接続詞**に注目する（しかし、だから、つまり）
- **指示語**（これ、それ、あれ）が何を指すか確認
- **段落の要点**をつかむ
                    """
                }
            ]
        }
    elif text_id == "japanese_modern_v2":
        return {
            "id": "japanese_modern_v2",
            "title": "中学国語 現代文 Vol.2",
            "subject": "国語",
            "chapters": [
                {
                    "title": "第1章: 小説・物語文の読解",
                    "content": """
# 小説・物語文の読解

## 1. 登場人物の心情
- **行動**から心情を読み取る
- **会話**から心情を読み取る
- **情景描写**から心情を読み取る

## 2. 場面の変化
- 時間の経過
- 場所の移動
- 登場人物の変化
                    """
                }
            ]
        }
    elif text_id == "japanese_classical_v1":
        return {
            "id": "japanese_classical_v1",
            "title": "中学国語 古文 Vol.1",
            "subject": "国語",
            "chapters": [
                {
                    "title": "第1章: 古文の基礎",
                    "content": """
# 古文の基礎

## 1. 歴史的仮名遣い
- **ハ行**: は→わ、ひ→い、ふ→う、へ→え、ほ→お
- **ワ行**: ゐ→い、ゑ→え、を→お

## 2. 基本的な古語
- **あり**: ある、いる
- **侍り（はべり）**: あります（丁寧語）
- **給ふ（たまふ）**: お〜になる（尊敬語）
- **奉る（たてまつる）**: 差し上げる（謙譲語）
                    """
                }
            ]
        }
    elif text_id == "japanese_classical_v2":
        return {
            "id": "japanese_classical_v2",
            "title": "中学国語 古文 Vol.2",
            "subject": "国語",
            "chapters": [
                {
                    "title": "第1章: 古典文法",
                    "content": """
# 古典文法

## 1. 助動詞
- **き・けり**: 過去
- **つ・ぬ**: 完了
- **む・べし**: 推量、意志
- **り・たり**: 完了、存続

## 2. 係り結びの法則
- **ぞ・なむ・や・か**: 連体形で結ぶ
- **こそ**: 已然形で結ぶ
                    """
                }
            ]
        }
    elif text_id == "japanese_kanbun_v1":
        return {
            "id": "japanese_kanbun_v1",
            "title": "中学国語 漢文 Vol.1",
            "subject": "国語",
            "chapters": [
                {
                    "title": "第1章: 漢文の基礎",
                    "content": """
# 漢文の基礎

## 1. 返り点
- **一二点**: 一→二の順に読む
- **上下点**: 上→下の順に読む
- **レ点**: すぐ下の字に返る

## 2. 書き下し文
- 返り点に従って日本語の語順に直す
- 送り仮名を補う
                    """
                }
            ]
        }
    elif text_id == "japanese_kanbun_v2":
        return {
            "id": "japanese_kanbun_v2",
            "title": "中学国語 漢文 Vol.2",
            "subject": "国語",
            "chapters": [
                {
                    "title": "第1章: 漢文の句法",
                    "content": """
# 漢文の句法

## 1. 否定形
- **不**: 〜ない
- **未**: まだ〜ない
- **無**: 〜がない

## 2. 疑問形
- **乎（か）**: 〜か
- **哉（や）**: 〜か（詠嘆）

## 3. 使役形
- **使**: 〜させる
                    """
                }
            ]
        }
    # High School Japanese
    elif text_id == "hs_japanese_modern_v1":
        return {
            "id": "hs_japanese_modern_v1",
            "title": "高校国語 現代文 Vol.1",
            "subject": "国語(高校)",
            "chapters": [
                {
                    "title": "第1章: 評論文の読解",
                    "content": """
# 評論文の読解

## 1. 論理展開の把握
- **主張**: 筆者が最も言いたいこと
- **根拠**: 主張を支える理由や事実
- **具体例**: 主張を分かりやすくする例

## 2. 抽象と具体
- 抽象的な概念を具体例で説明
- 具体例から抽象的な法則を導く
                    """
                }
            ]
        }
    elif text_id == "hs_japanese_modern_v2":
        return {
            "id": "hs_japanese_modern_v2",
            "title": "高校国語 現代文 Vol.2",
            "subject": "国語(高校)",
            "chapters": [
                {
                    "title": "第1章: 小説の読解",
                    "content": """
# 小説の読解

## 1. 語り手と視点
- **一人称**: 「私」が語る
- **三人称**: 客観的に語る
- **視点人物**: 誰の目を通して描かれているか

## 2. 表現技法
- **比喩**: 直喩（〜のような）、隠喩（〜だ）
- **象徴**: 抽象的な概念を具体物で表現
- **反復**: 同じ言葉や表現を繰り返す
                    """
                }
            ]
        }
    elif text_id == "hs_japanese_classical_v1":
        return {
            "id": "hs_japanese_classical_v1",
            "title": "高校国語 古文 Vol.1",
            "subject": "国語(高校)",
            "chapters": [
                {
                    "title": "第1章: 古典文法（動詞・形容詞）",
                    "content": """
# 古典文法（動詞・形容詞）

## 1. 動詞の活用
- **四段活用**: 書く（か・き・く・く・け・け）
- **上一段活用**: 着る（き・き・きる・きる・きれ・きよ）
- **下一段活用**: 蹴る（け・け・ける・ける・けれ・けよ）
- **上二段活用**: 起く（き・き・く・くる・くれ・きよ）
- **下二段活用**: 受く（け・け・く・くる・くれ・けよ）

## 2. 形容詞の活用
- **ク活用**: 美し（く・く・し・き・けれ・◯）
- **シク活用**: 楽し（しく・しく・し・しき・しけれ・◯）
                    """
                }
            ]
        }
    elif text_id == "hs_japanese_classical_v2":
        return {
            "id": "hs_japanese_classical_v2",
            "title": "高校国語 古文 Vol.2",
            "subject": "国語(高校)",
            "chapters": [
                {
                    "title": "第1章: 古典文法（助動詞）",
                    "content": """
# 古典文法（助動詞）

## 1. 過去・完了
- **き**: 過去（直接経験）
- **けり**: 過去（伝聞）、詠嘆
- **つ**: 完了（意志的動作）
- **ぬ**: 完了（自然的動作）
- **たり**: 完了・存続

## 2. 推量・意志
- **む**: 推量、意志、勧誘、仮定、婉曲
- **べし**: 推量、意志、可能、当然、命令、適当
- **らむ**: 現在推量
- **けむ**: 過去推量
                    """
                }
            ]
        }
    elif text_id == "hs_japanese_kanbun_v1":
        return {
            "id": "hs_japanese_kanbun_v1",
            "title": "高校国語 漢文 Vol.1",
            "subject": "国語(高校)",
            "chapters": [
                {
                    "title": "第1章: 漢文句法",
                    "content": """
# 漢文句法

## 1. 再読文字
- **未**: いまだ〜ず
- **将**: まさに〜んとす
- **須**: すべからく〜べし

## 2. 置き字
- **於**: 〜において（読まない）
- **于**: 〜において（読まない）
- **而**: しかして（省略可）
                    """
                }
            ]
        }
    elif text_id == "hs_japanese_kanbun_v2":
        return {
            "id": "hs_japanese_kanbun_v2",
            "title": "高校国語 漢文 Vol.2",
            "subject": "国語(高校)",
            "chapters": [
                {
                    "title": "第1章: 漢詩",
                    "content": """
# 漢詩

## 1. 漢詩の形式
- **絶句**: 4句（起承転結）
- **律詩**: 8句

## 2. 押韻
- 偶数句の最後の字の音を揃える
- 第1句も韻を踏むことがある
                    """
                }
            ]
        }
    # High School Math Advanced
    elif text_id == "hs_math_b_advanced":
        return {
            "id": "hs_math_b_advanced",
            "title": "高校数学 B 発展",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 統計的推測",
                    "content": """
# 統計的推測

## 1. 確率分布
- **二項分布**: $B(n, p)$
- **正規分布**: $N(m, \\sigma^2)$

## 2. 推定
- **点推定**: 母平均を標本平均で推定
- **区間推定**: 信頼区間を求める
  - 95%信頼区間: $\\bar{x} - 1.96\\frac{\\sigma}{\\sqrt{n}} \\leq m \\leq \\bar{x} + 1.96\\frac{\\sigma}{\\sqrt{n}}$
                    """
                }
            ]
        }
    elif text_id == "hs_math_c_advanced":
        return {
            "id": "hs_math_c_advanced",
            "title": "高校数学 C 発展",
            "subject": "数学(高校)",
            "chapters": [
                {
                    "title": "第1章: 式と曲線",
                    "content": """
# 式と曲線

## 1. 2次曲線
- **放物線**: $y^2 = 4px$
- **楕円**: $\\frac{x^2}{a^2} + \\frac{y^2}{b^2} = 1$
- **双曲線**: $\\frac{x^2}{a^2} - \\frac{y^2}{b^2} = 1$

## 2. 媒介変数表示
- $x = f(t)$, $y = g(t)$ で表される曲線
                    """
                },
                {
                    "title": "第2章: 行列",
                    "content": """
# 行列

## 1. 行列の演算
- 和: $A + B$
- 差: $A - B$
- 積: $AB$（行列の積は交換法則が成り立たない）

## 2. 逆行列
- $AA^{-1} = A^{-1}A = E$（単位行列）
- 2次正方行列の逆行列: $A = \\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$ のとき
  $$A^{-1} = \\frac{1}{ad-bc} \\begin{pmatrix} d & -b \\\\ -c & a \\end{pmatrix}$$
                    """
                }
            ]
        }
    # High School English Advanced
    elif text_id == "hs_eng_composition":
        return {
            "id": "hs_eng_composition",
            "title": "高校英語 英作文",
            "subject": "英語(高校)",
            "chapters": [
                {
                    "title": "第1章: 和文英訳",
                    "content": """
# 和文英訳

## 1. 基本方針
- 日本語を簡単な日本語に言い換える
- 知っている英語表現を使う
- 主語と動詞を明確にする

## 2. よくある間違い
- 直訳しすぎない
- 冠詞（a, the）を忘れない
- 時制に注意する
                    """
                },
                {
                    "title": "第2章: 自由英作文",
                    "content": """
# 自由英作文

## 1. 構成
- **序論**: 自分の意見を述べる
- **本論**: 理由や具体例を2〜3つ挙げる
- **結論**: 意見を再度述べる

## 2. 使える表現
- **First**, **Second**, **Finally**: 順序を示す
- **For example**: 例を挙げる
- **In conclusion**: 結論を述べる
                    """
                }
            ]
        }
    elif text_id == "hs_eng_interpretation":
        return {
            "id": "hs_eng_interpretation",
            "title": "高校英語 英文解釈",
            "subject": "英語(高校)",
            "chapters": [
                {
                    "title": "第1章: 構文解析",
                    "content": """
# 構文解析

## 1. 文型の把握
- SV, SVC, SVO, SVOO, SVOC の5文型を見抜く
- 主語（S）と動詞（V）を最初に見つける

## 2. 修飾関係
- **形容詞句・節**: 名詞を修飾
- **副詞句・節**: 動詞、形容詞、副詞を修飾

## 3. 難解な構文
- **倒置**: 強調のため語順が変わる
- **省略**: 繰り返しを避けるため省略される
- **挿入**: 補足説明が挿入される
                    """
                }
            ]
        }
    elif text_id == "hs_eng_listening":
        return {
            "id": "hs_eng_listening",
            "title": "高校英語 リスニング",
            "subject": "英語(高校)",
            "chapters": [
                {
                    "title": "第1章: リスニング対策",
                    "content": """
# リスニング対策

## 1. 聞き取りのコツ
- **キーワード**に集中する
- **数字・固有名詞**をメモする
- **話の流れ**を追う

## 2. 音の変化
- **連結**: 子音+母音がつながる（an apple → アナップル）
- **脱落**: 音が消える（good boy → グッボーイ）
- **同化**: 音が変わる（want to → ワナ）

## 3. 練習方法
- **シャドーイング**: 聞こえた英語をすぐに真似して言う
- **ディクテーション**: 聞こえた英語を書き取る
                    """
                }
            ]
        }
    # Elementary School Math (Grades 1-6)
    elif text_id == "elem_math_1":
        return {"id": "elem_math_1", "title": "小学算数 1年", "subject": "算数", "chapters": [{"title": "第1章: かずとけいさん", "content": "# かずとけいさん\n\n## 1. 10までのかず\n- 1, 2, 3, 4, 5, 6, 7, 8, 9, 10\n\n## 2. たしざん\n- 2 + 3 = 5\n- 4 + 1 = 5"}]}
    elif text_id == "elem_math_2":
        return {"id": "elem_math_2", "title": "小学算数 2年", "subject": "算数", "chapters": [{"title": "第1章: たし算とひき算", "content": "# たし算とひき算\n\n## 1. 2けたのたし算\n- 23 + 15 = 38\n\n## 2. 九九\n- 2の段、3の段、4の段..."}]}
    elif text_id == "elem_math_3":
        return {"id": "elem_math_3", "title": "小学算数 3年", "subject": "算数", "chapters": [{"title": "第1章: かけ算とわり算", "content": "# かけ算とわり算\n\n## 1. かけ算の筆算\n- 23 × 4 = 92\n\n## 2. わり算\n- 12 ÷ 3 = 4"}]}
    elif text_id == "elem_math_4":
        return {"id": "elem_math_4", "title": "小学算数 4年", "subject": "算数", "chapters": [{"title": "第1章: 大きな数と計算", "content": "# 大きな数と計算\n\n## 1. 億・兆\n- 1億 = 100,000,000\n\n## 2. 小数\n- 0.1, 0.01"}]}
    elif text_id == "elem_math_5":
        return {"id": "elem_math_5", "title": "小学算数 5年", "subject": "算数", "chapters": [{"title": "第1章: 分数と小数", "content": "# 分数と小数\n\n## 1. 分数のたし算・ひき算\n- $\\frac{1}{2} + \\frac{1}{3} = \\frac{5}{6}$\n\n## 2. 小数のかけ算・わり算"}]}
    elif text_id == "elem_math_6":
        return {"id": "elem_math_6", "title": "小学算数 6年", "subject": "算数", "chapters": [{"title": "第1章: 分数のかけ算・わり算", "content": "# 分数のかけ算・わり算\n\n## 1. 分数×分数\n- $\\frac{2}{3} \\times \\frac{3}{4} = \\frac{1}{2}$\n\n## 2. 比と比例"}]}
    
    # Elementary School Japanese (Grades 1-6)
    elif text_id == "elem_japanese_1":
        return {"id": "elem_japanese_1", "title": "小学国語 1年", "subject": "国語", "chapters": [{"title": "第1章: ひらがな・カタカナ", "content": "# ひらがな・カタカナ\n\n## 1. ひらがな\n- あいうえお、かきくけこ\n\n## 2. カタカナ\n- アイウエオ、カキクケコ"}]}
    elif text_id == "elem_japanese_2":
        return {"id": "elem_japanese_2", "title": "小学国語 2年", "subject": "国語", "chapters": [{"title": "第1章: かん字", "content": "# かん字\n\n## 1. 1年生のかん字\n- 一、二、三、四、五\n\n## 2. 2年生のかん字\n- 学、校、先、生"}]}
    elif text_id == "elem_japanese_3":
        return {"id": "elem_japanese_3", "title": "小学国語 3年", "subject": "国語", "chapters": [{"title": "第1章: 漢字と文章", "content": "# 漢字と文章\n\n## 1. 3年生の漢字\n- 物、事、使、方\n\n## 2. 物語文の読み方"}]}
    elif text_id == "elem_japanese_4":
        return {"id": "elem_japanese_4", "title": "小学国語 4年", "subject": "国語", "chapters": [{"title": "第1章: 説明文と物語文", "content": "# 説明文と物語文\n\n## 1. 説明文の読み方\n- 段落の要点をつかむ\n\n## 2. 物語文の読み方\n- 登場人物の気持ち"}]}
    elif text_id == "elem_japanese_5":
        return {"id": "elem_japanese_5", "title": "小学国語 5年", "subject": "国語", "chapters": [{"title": "第1章: 文章の構成", "content": "# 文章の構成\n\n## 1. 序論・本論・結論\n\n## 2. 敬語\n- 尊敬語、謙譲語、丁寧語"}]}
    elif text_id == "elem_japanese_6":
        return {"id": "elem_japanese_6", "title": "小学国語 6年", "subject": "国語", "chapters": [{"title": "第1章: 論説文と古典", "content": "# 論説文と古典\n\n## 1. 論説文の読解\n- 筆者の主張を読み取る\n\n## 2. 古典入門\n- 竹取物語、枕草子"}]}
    
    # Elementary School Science (Grades 3-6)
    elif text_id == "elem_science_3":
        return {"id": "elem_science_3", "title": "小学理科 3年", "subject": "理科", "chapters": [{"title": "第1章: しぜんのかんさつ", "content": "# しぜんのかんさつ\n\n## 1. こん虫\n- からだのつくり（頭・むね・はら）\n\n## 2. 植物\n- たねのまき方"}]}
    elif text_id == "elem_science_4":
        return {"id": "elem_science_4", "title": "小学理科 4年", "subject": "理科", "chapters": [{"title": "第1章: 季節と生物", "content": "# 季節と生物\n\n## 1. 春の生物\n\n## 2. 電気のはたらき\n- 乾電池、豆電球"}]}
    elif text_id == "elem_science_5":
        return {"id": "elem_science_5", "title": "小学理科 5年", "subject": "理科", "chapters": [{"title": "第1章: 植物の発芽と成長", "content": "# 植物の発芽と成長\n\n## 1. 発芽の条件\n- 水、空気、温度\n\n## 2. 天気の変化\n- 雲の動き"}]}
    elif text_id == "elem_science_6":
        return {"id": "elem_science_6", "title": "小学理科 6年", "subject": "理科", "chapters": [{"title": "第1章: 燃焼と水溶液", "content": "# 燃焼と水溶液\n\n## 1. ものの燃え方\n- 酸素が必要\n\n## 2. 水溶液の性質\n- 酸性、中性、アルカリ性"}]}
    
    # Elementary School Social Studies (Grades 3-6)
    elif text_id == "elem_social_3":
        return {"id": "elem_social_3", "title": "小学社会 3年", "subject": "社会", "chapters": [{"title": "第1章: わたしたちのまち", "content": "# わたしたちのまち\n\n## 1. まちのようす\n\n## 2. まちではたらく人"}]}
    elif text_id == "elem_social_4":
        return {"id": "elem_social_4", "title": "小学社会 4年", "subject": "社会", "chapters": [{"title": "第1章: 都道府県", "content": "# 都道府県\n\n## 1. 47都道府県\n\n## 2. 地図の見方"}]}
    elif text_id == "elem_social_5":
        return {"id": "elem_social_5", "title": "小学社会 5年", "subject": "社会", "chapters": [{"title": "第1章: 日本の国土", "content": "# 日本の国土\n\n## 1. 日本の位置\n\n## 2. 気候の特色"}]}
    elif text_id == "elem_social_6":
        return {"id": "elem_social_6", "title": "小学社会 6年", "subject": "社会", "chapters": [{"title": "第1章: 日本の歴史", "content": "# 日本の歴史\n\n## 1. 縄文時代・弥生時代\n\n## 2. 飛鳥時代・奈良時代"}]}
    
    # Practical Subjects
    elif text_id == "music_theory":
        return {"id": "music_theory", "title": "音楽 楽典", "subject": "音楽", "chapters": [{"title": "第1章: 楽譜の読み方", "content": "# 楽譜の読み方\n\n## 1. 音符と休符\n- 全音符、2分音符、4分音符、8分音符\n\n## 2. 音階\n- ドレミファソラシド"}]}
    elif text_id == "music_history":
        return {"id": "music_history", "title": "音楽 音楽史", "subject": "音楽", "chapters": [{"title": "第1章: 西洋音楽史", "content": "# 西洋音楽史\n\n## 1. バロック時代\n- バッハ、ヘンデル\n\n## 2. 古典派\n- モーツァルト、ベートーヴェン"}]}
    elif text_id == "art_history":
        return {"id": "art_history", "title": "美術 美術史", "subject": "美術", "chapters": [{"title": "第1章: 西洋美術史", "content": "# 西洋美術史\n\n## 1. ルネサンス\n- レオナルド・ダ・ヴィンチ、ミケランジェロ\n\n## 2. 印象派\n- モネ、ルノワール"}]}
    elif text_id == "art_technique":
        return {"id": "art_technique", "title": "美術 技法", "subject": "美術", "chapters": [{"title": "第1章: 絵画技法", "content": "# 絵画技法\n\n## 1. デッサン\n- 鉛筆の使い方\n\n## 2. 水彩画\n- 透明水彩、不透明水彩"}]}
    elif text_id == "health":
        return {"id": "health", "title": "保健体育 保健", "subject": "保健体育", "chapters": [{"title": "第1章: 健康な生活", "content": "# 健康な生活\n\n## 1. 生活習慣\n- 睡眠、運動、食事\n\n## 2. 病気の予防\n- 感染症の予防"}]}
    elif text_id == "pe_theory":
        return {"id": "pe_theory", "title": "保健体育 体育理論", "subject": "保健体育", "chapters": [{"title": "第1章: スポーツの意義", "content": "# スポーツの意義\n\n## 1. スポーツの歴史\n\n## 2. フェアプレー精神"}]}
    elif text_id == "technology":
        return {"id": "technology", "title": "技術・家庭 技術分野", "subject": "技術・家庭", "chapters": [{"title": "第1章: 材料と加工", "content": "# 材料と加工\n\n## 1. 木材加工\n- のこぎり、かんな\n\n## 2. 金属加工"}]}
    elif text_id == "home_economics":
        return {"id": "home_economics", "title": "技術・家庭 家庭分野", "subject": "技術・家庭", "chapters": [{"title": "第1章: 食生活", "content": "# 食生活\n\n## 1. 栄養素\n- 炭水化物、タンパク質、脂質、ビタミン、ミネラル\n\n## 2. 調理の基本"}]}
    
    # Exam Prep
    elif text_id == "common_test_math":
        return {"id": "common_test_math", "title": "共通テスト対策 数学", "subject": "大学受験", "chapters": [{"title": "第1章: 共通テスト数学攻略法", "content": "# 共通テスト数学攻略法\n\n## 1. 時間配分\n- 数学IA: 70分、数学IIB: 60分\n\n## 2. 頻出分野\n- 二次関数、三角関数、微積分"}]}
    elif text_id == "common_test_english":
        return {"id": "common_test_english", "title": "共通テスト対策 英語", "subject": "大学受験", "chapters": [{"title": "第1章: 共通テスト英語攻略法", "content": "# 共通テスト英語攻略法\n\n## 1. リーディング\n- 速読のコツ\n\n## 2. リスニング\n- 先読みの重要性"}]}
    elif text_id == "common_test_japanese":
        return {"id": "common_test_japanese", "title": "共通テスト対策 国語", "subject": "大学受験", "chapters": [{"title": "第1章: 共通テスト国語攻略法", "content": "# 共通テスト国語攻略法\n\n## 1. 現代文\n- 選択肢の絞り方\n\n## 2. 古文・漢文\n- 文法知識の活用"}]}
    elif text_id == "essay_writing":
        return {"id": "essay_writing", "title": "小論文対策", "subject": "大学受験", "chapters": [{"title": "第1章: 小論文の書き方", "content": "# 小論文の書き方\n\n## 1. 構成\n- 序論・本論・結論\n\n## 2. 論理展開\n- 主張と根拠"}]}
    elif text_id == "secondary_exam_math":
        return {"id": "secondary_exam_math", "title": "二次試験対策 数学", "subject": "大学受験", "chapters": [{"title": "第1章: 記述式数学", "content": "# 記述式数学\n\n## 1. 答案の書き方\n- 論理的に記述する\n\n## 2. 頻出問題\n- 微積分、ベクトル"}]}
    elif text_id == "secondary_exam_english":
        return {"id": "secondary_exam_english", "title": "二次試験対策 英語", "subject": "大学受験", "chapters": [{"title": "第1章: 記述式英語", "content": "# 記述式英語\n\n## 1. 英作文\n- 自由英作文の型\n\n## 2. 和文英訳\n- 日本語の言い換え"}]}
    
    # Certifications
    elif text_id == "eiken_3":
        return {"id": "eiken_3", "title": "英検3級対策", "subject": "資格試験", "chapters": [{"title": "第1章: 英検3級の概要", "content": "# 英検3級の概要\n\n## 1. 試験内容\n- 筆記、リスニング、面接\n\n## 2. 頻出単語\n- 中学卒業レベル"}]}
    elif text_id == "eiken_pre2":
        return {"id": "eiken_pre2", "title": "英検準2級対策", "subject": "資格試験", "chapters": [{"title": "第1章: 英検準2級の概要", "content": "# 英検準2級の概要\n\n## 1. 試験内容\n- 筆記、リスニング、面接\n\n## 2. 頻出文法\n- 仮定法、関係代名詞"}]}
    elif text_id == "eiken_2":
        return {"id": "eiken_2", "title": "英検2級対策", "subject": "資格試験", "chapters": [{"title": "第1章: 英検2級の概要", "content": "# 英検2級の概要\n\n## 1. 試験内容\n- 筆記、リスニング、面接\n\n## 2. ライティング\n- 意見論述型"}]}
    elif text_id == "eiken_pre1":
        return {"id": "eiken_pre1", "title": "英検準1級対策", "subject": "資格試験", "chapters": [{"title": "第1章: 英検準1級の概要", "content": "# 英検準1級の概要\n\n## 1. 試験内容\n- 筆記、リスニング、面接\n\n## 2. 語彙力強化\n- 7500〜9000語レベル"}]}
    elif text_id == "suken":
        return {"id": "suken", "title": "数学検定対策", "subject": "資格試験", "chapters": [{"title": "第1章: 数学検定の概要", "content": "# 数学検定の概要\n\n## 1. 級別レベル\n- 3級: 中学3年、準2級: 高校1年\n\n## 2. 出題範囲"}]}
    elif text_id == "kanken":
        return {"id": "kanken", "title": "漢字検定対策", "subject": "資格試験", "chapters": [{"title": "第1章: 漢字検定の概要", "content": "# 漢字検定の概要\n\n## 1. 級別レベル\n- 3級: 中学卒業、2級: 高校卒業\n\n## 2. 出題形式\n- 読み、書き、部首"}]}
    # Programming & IT
    elif text_id == "programming_scratch":
        return {"id": "programming_scratch", "title": "プログラミング入門 Scratch", "subject": "プログラミング", "chapters": [{"title": "第1章: Scratchの基本", "content": "# Scratchの基本\n\n## 1. ブロックプログラミング\n- 動き、見た目、音のブロック\n\n## 2. 簡単なゲーム作り\n- キャラクターを動かす"}]}
    elif text_id == "programming_python":
        return {"id": "programming_python", "title": "プログラミング入門 Python", "subject": "プログラミング", "chapters": [{"title": "第1章: Pythonの基本", "content": "# Pythonの基本\n\n## 1. 変数と演算\n```python\nx = 10\ny = 20\nprint(x + y)\n```\n\n## 2. 条件分岐とループ\n- if文、for文、while文"}]}
    elif text_id == "programming_info1":
        return {"id": "programming_info1", "title": "高校 情報I", "subject": "プログラミング", "chapters": [{"title": "第1章: 情報社会", "content": "# 情報社会\n\n## 1. 情報モラル\n- 著作権、個人情報保護\n\n## 2. アルゴリズム\n- フローチャート、プログラミング"}]}
    elif text_id == "eng_speaking":
        return {"id": "eng_speaking", "title": "英語 スピーキング対策", "subject": "英語", "chapters": [{"title": "第1章: スピーキング練習法", "content": "# スピーキング練習法\n\n## 1. 音読\n- 毎日10分の音読習慣\n\n## 2. シャドーイング\n- ネイティブの音声を真似る"}]}
    elif text_id == "eng_writing_advanced":
        return {"id": "eng_writing_advanced", "title": "英語 ライティング発展", "subject": "英語", "chapters": [{"title": "第1章: パラグラフライティング", "content": "# パラグラフライティング\n\n## 1. トピックセンテンス\n- 段落の主題を明確に\n\n## 2. サポーティングセンテンス\n- 具体例や理由で補強"}]}
    elif text_id == "eng_pronunciation":
        return {"id": "eng_pronunciation", "title": "英語 発音・アクセント", "subject": "英語", "chapters": [{"title": "第1章: 発音の基礎", "content": "# 発音の基礎\n\n## 1. 母音と子音\n- /æ/, /ə/, /θ/, /ð/ など\n\n## 2. アクセントの位置"}]}
    elif text_id == "math_olympiad":
        return {"id": "math_olympiad", "title": "数学オリンピック対策", "subject": "数学", "chapters": [{"title": "第1章: 整数問題", "content": "# 整数問題\n\n## 1. 素数と合成数\n\n## 2. 不定方程式"}]}
    elif text_id == "physics_olympiad":
        return {"id": "physics_olympiad", "title": "物理オリンピック対策", "subject": "物理", "chapters": [{"title": "第1章: 力学の応用", "content": "# 力学の応用\n\n## 1. 運動方程式の応用"}]}
    elif text_id == "chemistry_olympiad":
        return {"id": "chemistry_olympiad", "title": "化学オリンピック対策", "subject": "化学", "chapters": [{"title": "第1章: 化学反応の速度論", "content": "# 化学反応の速度論\n\n## 1. 反応速度式"}]}
    elif text_id == "biology_olympiad":
        return {"id": "biology_olympiad", "title": "生物オリンピック対策", "subject": "生物", "chapters": [{"title": "第1章: 分子生物学", "content": "# 分子生物学\n\n## 1. DNA複製"}]}
    elif text_id == "presentation":
        return {"id": "presentation", "title": "プレゼンテーション技法", "subject": "実用スキル", "chapters": [{"title": "第1章: プレゼンの基本", "content": "# プレゼンの基本\n\n## 1. 構成\n- 導入・本論・結論\n\n## 2. スライド作成"}]}
    elif text_id == "report_writing":
        return {"id": "report_writing", "title": "レポート・論文の書き方", "subject": "実用スキル", "chapters": [{"title": "第1章: レポートの構成", "content": "# レポートの構成\n\n## 1. 序論\n- 研究の背景と目的\n\n## 2. 本論"}]}
    elif text_id == "study_methods":
        return {"id": "study_methods", "title": "ノート術・勉強法", "subject": "実用スキル", "chapters": [{"title": "第1章: 効果的な勉強法", "content": "# 効果的な勉強法\n\n## 1. ノート術\n- コーネル式ノート\n\n## 2. 記憶法\n- 分散学習"}]}
    elif text_id == "toeic":
        return {"id": "toeic", "title": "TOEIC対策", "subject": "資格試験", "chapters": [{"title": "第1章: TOEICの概要", "content": "# TOEICの概要\n\n## 1. 試験形式\n- リスニング（100問）\n- リーディング（100問）"}]}
    elif text_id == "toefl":
        return {"id": "toefl", "title": "TOEFL対策", "subject": "資格試験", "chapters": [{"title": "第1章: TOEFLの概要", "content": "# TOEFLの概要\n\n## 1. 試験形式\n- Reading, Listening, Speaking, Writing"}]}
    elif text_id == "gtec":
        return {"id": "gtec", "title": "GTEC対策", "subject": "資格試験", "chapters": [{"title": "第1章: GTECの概要", "content": "# GTECの概要\n\n## 1. 試験形式\n- 4技能"}]}
    elif text_id == "advanced_calculus":
        return {"id": "advanced_calculus", "title": "微分積分 発展", "subject": "数学", "chapters": [{"title": "第1章: 多変数関数", "content": "# 多変数関数\n\n## 1. 偏微分\n\n## 2. 重積分"}]}
    elif text_id == "linear_algebra":
        return {"id": "linear_algebra", "title": "線形代数", "subject": "数学", "chapters": [{"title": "第1章: ベクトル空間", "content": "# ベクトル空間\n\n## 1. 線形独立\n\n## 2. 基底と次元"}]}
    elif text_id == "probability_stats":
        return {"id": "probability_stats", "title": "確率統計 発展", "subject": "数学", "chapters": [{"title": "第1章: 確率分布", "content": "# 確率分布\n\n## 1. 離散分布\n\n## 2. 連続分布"}]}
    elif text_id == "quantum_physics":
        return {"id": "quantum_physics", "title": "量子力学入門", "subject": "物理", "chapters": [{"title": "第1章: 量子の世界", "content": "# 量子の世界\n\n## 1. 波動と粒子の二重性"}]}
    elif text_id == "organic_chem_advanced":
        return {"id": "organic_chem_advanced", "title": "有機化学 発展", "subject": "化学", "chapters": [{"title": "第1章: 反応機構", "content": "# 反応機構\n\n## 1. 求核置換反応"}]}
    elif text_id == "molecular_biology":
        return {"id": "molecular_biology", "title": "分子生物学 発展", "subject": "生物", "chapters": [{"title": "第1章: 遺伝子発現制御", "content": "# 遺伝子発現制御\n\n## 1. 転写制御"}]}
    elif text_id == "world_literature":
        return {"id": "world_literature", "title": "世界文学", "subject": "国語", "chapters": [{"title": "第1章: 西洋文学", "content": "# 西洋文学\n\n## 1. ギリシャ悲劇\n\n## 2. シェイクスピア"}]}
    elif text_id == "philosophy":
        return {"id": "philosophy", "title": "哲学入門", "subject": "社会", "chapters": [{"title": "第1章: 西洋哲学史", "content": "# 西洋哲学史\n\n## 1. 古代ギリシャ哲学\n\n## 2. 近代哲学"}]}
    elif text_id == "economics":
        return {"id": "economics", "title": "経済学入門", "subject": "社会", "chapters": [{"title": "第1章: ミクロ経済学", "content": "# ミクロ経済学\n\n## 1. 需要と供給\n\n## 2. 弾力性"}]}
    elif text_id == "eng_vocab":
        return {
            "id": "eng_vocab",
            "title": "英単語ターゲット1000",
            "subject": "英語",
            "chapters": [
                {
                    "title": "Section 1: 重要動詞",
                    "content": """
# Section 1: 重要動詞

1. **follow** (〜に従う、ついていく)
   - Follow the rules.
2. **consider** (〜を考慮する)
   - I will consider it.
3. **increase** (増える、増やす)
   - The number is increasing.
4. **expect** (予期する)
   - I expect him to come.
5. **decide** (決める)
   - I decided to go.
6. **develop** (発達させる)
   - develop a new technology.
7. **provide** (供給する)
   - provide food for them.
8. **continue** (続く、続ける)
   - Rain continued all day.
9. **include** (含む)
   - Try to include vegetables in your diet.
10. **remain** (〜のままである)
    - remain silent.
"""
                }
            ]
        }
    elif text_id == "math_v2":
        return {
            "id": "math_v2",
            "title": "中学数学 Vol.2 (図形)",
            "subject": "数学",
            "chapters": [
                {
                    "title": "第1章: 平面図形",
                    "content": """
# 平面図形

## 1. 図形の移動
- **平行移動**: 形を変えずに一定の方向にずらす。
- **回転移動**: ある点を中心に回転させる。
- **対称移動**: 直線を折り目として折り返す。

## 2. おうぎ形
半径 $r$, 中心角 $a^\\circ$ のおうぎ形について
- **弧の長さ** $l$:
$$ l = 2\\pi r \\times \\frac{a}{360} $$
- **面積** $S$:
$$ S = \\pi r^2 \\times \\frac{a}{360} $$
"""
                },
                {
                    "title": "第2章: 図形の合同",
                    "content": """
# 図形の合同

## 1. 合同条件（三角形）
2つの三角形が合同であるための条件。
1. **3組の辺がそれぞれ等しい**
2. **2組の辺とその間の角がそれぞれ等しい**
3. **1組の辺とその両端の角がそれぞれ等しい**

## 2. 証明の進め方
1. 「仮定」を確認する。
2. 「結論」を確認する。
3. 根拠となる「性質」や「条件」を使って筋道を立てる。
"""
                }
            ]
        }
    else:
        raise HTTPException(status_code=404, detail="Text not found")

# --- Virtual Study Room ---

@app.post("/enter_study_room")
async def enter_study_room(user_id: str = Body(...), username: str = Body(...)):
    try:
        # Update user's presence
        db.collection('study_room').document(user_id).set({
            'username': username,
            'joined_at': datetime.now(timezone.utc),
            'last_active': datetime.now(timezone.utc),
            'status': 'studying'
        })
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/study_room_users")
async def get_study_room_users():
    try:
        # Get users active in the last 5 minutes
        active_threshold = datetime.now(timezone.utc) - timedelta(minutes=5)
        docs = db.collection('study_room')\
            .where(filter=firestore.FieldFilter('last_active', '>=', active_threshold))\
            .stream()
            
        users = []
        for doc in docs:
            data = doc.to_dict()
            users.append(data)
            
        # Add some AI bots if room is empty or sparse
        if len(users) < 3:
            users.extend([
                {'username': 'AI田中', 'status': 'studying', 'joined_at': '2024-01-01'},
                {'username': 'AI佐藤', 'status': 'focused', 'joined_at': '2024-01-01'},
            ])
            
        return {"users": users}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- Auto Flashcards ---

@app.post("/generate_flashcards")
async def generate_flashcards(user_id: str = Body(...), subject: str = Body(...)):
    try:
        # In a real app, we would fetch recent mistakes or study logs.
        # For now, we'll generate based on the subject.
        
        prompt = f"""
        「{subject}」に関する暗記カード（単語帳）を5枚作成してください。
        中学生レベルの重要な用語や単語を選んでください。
        
        出力フォーマット(JSON):
        {{
            "cards": [
                {{"front": "表面（用語や問題）", "back": "裏面（意味や答え）"}},
                ...
            ]
        }}
        ※キー名は必ず "front" と "back" にしてください。
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        result = json.loads(clean_json_text(response.text))
        
        # Validate and normalize keys
        cards = []
        for card in result.get('cards', []):
            front = card.get('front') or card.get('Front') or card.get('term') or "No Content"
            back = card.get('back') or card.get('Back') or card.get('definition') or "No Content"
            cards.append({"front": front, "back": back})
            
        return {"status": "success", "cards": cards}

    except Exception as e:
        print(f"Generate Flashcards Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Spaced Repetition System (SRS) ---

class ReviewItem(BaseModel):
    user_id: str
    item_id: str
    content: str # JSON string of card content
    subject: str

class ReviewUpdate(BaseModel):
    user_id: str
    item_id: str
    quality: int # 0-5 scale

@app.post("/register_review_item")
async def register_review_item(item: ReviewItem):
    try:
        # Initial state
        db.collection('users').document(item.user_id).collection('reviews').document(item.item_id).set({
            'content': item.content,
            'subject': item.subject,
            'next_review': datetime.now(timezone.utc),
            'interval': 1, # Days
            'repetition': 0,
            'ef': 2.5 # Easiness Factor
        })
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/due_reviews/{user_id}")
async def get_due_reviews(user_id: str):
    try:
        now = datetime.now(timezone.utc)
        docs = db.collection('users').document(user_id).collection('reviews')\
            .where(filter=firestore.FieldFilter('next_review', '<=', now))\
            .stream()
            
        items = []
        for doc in docs:
            data = doc.to_dict()
            data['item_id'] = doc.id
            items.append(data)
            
        return {"items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/update_review_status")
async def update_review_status(update: ReviewUpdate):
    try:
        doc_ref = db.collection('users').document(update.user_id).collection('reviews').document(update.item_id)
        doc = doc_ref.get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail="Item not found")
            
        data = doc.to_dict()
        interval = data.get('interval', 1)
        repetition = data.get('repetition', 0)
        ef = data.get('ef', 2.5)
        
        # Simplified SM-2 Algorithm
        if update.quality >= 3:
            if repetition == 0:
                interval = 1
            elif repetition == 1:
                interval = 6
            else:
                interval = int(interval * ef)
            repetition += 1
            ef = ef + (0.1 - (5 - update.quality) * (0.08 + (5 - update.quality) * 0.02))
        else:
            repetition = 0
            interval = 1
            
        if ef < 1.3:
            ef = 1.3
            
        next_review = datetime.now(timezone.utc) + timedelta(days=interval)
        
        doc_ref.update({
            'next_review': next_review,
            'interval': interval,
            'repetition': repetition,
            'ef': ef
        })
        
        return {"status": "success", "next_review": next_review}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- AI Mock Interview ---

@app.post("/mock_interview")
async def mock_interview(
    file: UploadFile = File(...),
    interview_type: str = Form("university_entrance") # university_entrance, job_hunting
):
    try:
        # Save temporary file
        temp_filename = f"temp_interview_{file.filename}"
        with open(temp_filename, "wb") as buffer:
            buffer.write(await file.read())

        # Upload to Gemini
        audio_file = genai.upload_file(temp_filename, mime_type=file.content_type)
        
        system_prompt = ""
        if interview_type == "university_entrance":
            system_prompt = "あなたは大学入試の面接官です。志望動機や高校生活について質問し、生徒の回答に対して深掘りしてください。威圧的すぎず、しかし鋭い質問を投げかけてください。"
        else:
            system_prompt = "あなたは企業の採用面接官です。自己PRやガクチカ（学生時代に力を入れたこと）について質問してください。論理的思考力やコミュニケーション能力を見極めるつもりで接してください。"

        prompt = f"""
        {system_prompt}
        
        ユーザーの音声（回答）を聞き取り、以下のJSON形式で返答してください。
        {{
            "reply": "面接官としての次の質問、またはリアクション",
            "feedback": "今の回答に対するフィードバック（良かった点、改善点）。面接中は言わず、心の中のメモとして記録します。"
        }}
        """

        response = model.generate_content([prompt, audio_file], generation_config={"response_mime_type": "application/json"})
        result = json.loads(clean_json_text(response.text))
        
        # Cleanup
        os.remove(temp_filename)
        
        return result

    except Exception as e:
        print(f"Mock Interview Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Class Recorder & Summary ---

@app.post("/summarize_class")
async def summarize_class(file: UploadFile = File(...)):
    try:
        # Save temporary file
        temp_filename = f"temp_class_{file.filename}"
        with open(temp_filename, "wb") as buffer:
            buffer.write(await file.read())

        # Upload to Gemini
        audio_file = genai.upload_file(temp_filename, mime_type=file.content_type)
        
        prompt = """
        あなたは優秀なノートテイカーです。
        アップロードされた授業の音声を聞き取り、以下のJSON形式で出力してください。
        
        {
            "summary": "授業の要約（箇条書きで分かりやすく）",
            "keywords": ["重要語句1", "重要語句2", ...],
            "quiz": [
                {"question": "授業内容に関するクイズ1", "answer": "答え"},
                {"question": "授業内容に関するクイズ2", "answer": "答え"}
            ]
        }
        """

        response = model.generate_content([prompt, audio_file], generation_config={"response_mime_type": "application/json"})
        result = json.loads(clean_json_text(response.text))
        
        # Cleanup
        os.remove(temp_filename)
        
        return result

    except Exception as e:
        print(f"Summarize Class Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- AI Debate ---

class DebateRequest(BaseModel):
    topic: str
    user_argument: str
    history: list = [] # List of {"role": "user"|"ai", "text": "..."}

@app.post("/debate")
async def debate(request: DebateRequest):
    try:
        prompt = f"""
        あなたはディベートの対戦相手です。
        テーマ: 「{request.topic}」
        
        あなたの役割: ユーザーの意見に対して、論理的な反論（反対意見）を述べてください。
        感情的にならず、あくまで論理と証拠に基づいて議論を深めてください。
        
        これまでの議論の履歴:
        {request.history}
        
        ユーザーの最新の主張:
        {request.user_argument}
        
        出力フォーマット(JSON):
        {{
            "rebuttal": "あなたの反論（日本語）",
            "logic_score": 80, // ユーザーの主張の論理性を0-100で評価
            "advice": "より説得力を高めるためのアドバイス"
        }}
        """

        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        result = json.loads(clean_json_text(response.text))
        
        return result

    except Exception as e:
        print(f"Debate Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- AI Textbook & Drill ---

@app.post("/generate_textbook")
async def generate_textbook(topic: str = Body(...), grade: str = Body(...)):
    try:
        prompt = f"""
        あなたはプロの教科書編集者です。
        対象学年: {grade}
        テーマ: {topic}
        
        このテーマについて、分かりやすく解説する「教科書の1章分」を作成してください。
        
        構成:
        1. **導入**: なぜこれを学ぶのか？身近な例。
        2. **本論**: 重要な概念の解説（図解が必要な箇所は [図: 〜の説明] と記述）。
        3. **まとめ**: ポイントの整理。
        
        出力形式: Markdown
        """
        
        response = model.generate_content(prompt)
        return {"content": response.text}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/generate_drill")
async def generate_drill(topic: str = Body(...), grade: str = Body(...)):
    try:
        prompt = f"""
        あなたはプロの塾講師です。
        対象学年: {grade}
        テーマ: {topic}
        
        このテーマに関する「確認ドリル」を5問作成してください。
        形式: 4択問題
        
        出力フォーマット(JSON):
        {{
            "drills": [
                {{
                    "question": "問題文",
                    "options": ["選択肢1", "選択肢2", "選択肢3", "選択肢4"],
                    "answer": "正解の選択肢（文字列）",
                    "explanation": "解説"
                }},
                ...
            ]
        }}
        """
        
        response = model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        result = json.loads(clean_json_text(response.text))
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- Community Content Sharing ---

class ShareContentRequest(BaseModel):
    title: str
    type: str # textbook, drill
    content: str # JSON string or Markdown text
    author: str = "Anonymous"

@app.post("/share_content")
async def share_content(request: ShareContentRequest):
    try:
        doc_ref = db.collection("shared_content").document()
        doc_ref.set({
            "title": request.title,
            "type": request.type,
            "content": request.content,
            "author": request.author,
            "created_at": firestore.SERVER_TIMESTAMP
        })
        return {"status": "success", "id": doc_ref.id}
    except Exception as e:
        print(f"Share Content Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/shared_content")
async def get_shared_content():
    try:
        docs = db.collection("shared_content").order_by("created_at", direction=firestore.Query.DESCENDING).limit(20).stream()
        result = []
        for doc in docs:
            data = doc.to_dict()
            # Convert timestamp to string
            if "created_at" in data and data["created_at"]:
                 data["created_at"] = data["created_at"].isoformat()
            data["id"] = doc.id
            result.append(data)
        return {"contents": result}
    except Exception as e:
        print(f"Get Shared Content Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
