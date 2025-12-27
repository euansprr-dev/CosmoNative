#!/usr/bin/env python3
"""
CosmoOS FunctionGemma Training Data Generator

Generates 15,000+ training examples for fine-tuning FunctionGemma 270M
on CosmoOS voice commands.

Output format follows FunctionGemma's expected structure:
{
  "messages": [
    {"role": "developer", "content": "System prompt..."},
    {"role": "user", "content": "User command..."},
    {"role": "model", "content": "<start_function_call>call:FUNC{params}<end_function_call>"}
  ]
}

Categories:
1. Simple Entity Creation (4,000 examples)
2. Project-Specific Creation (2,500 examples)
3. Timed Entity Creation (2,000 examples)
4. Entity Modification (1,500 examples)
5. Level System Queries (2,000 examples) - NEW!
6. Deep Work Commands (1,000 examples) - NEW!
7. Journal Commands (1,000 examples) - NEW!
8. Batch/Brain Dump (500 examples)
9. Navigate (600 examples)

Usage:
    python generate_training_data.py
"""

import json
import random
import os
from datetime import datetime, timedelta
from pathlib import Path

# Output directory
OUTPUT_DIR = Path(__file__).parent / "training_data"
OUTPUT_DIR.mkdir(exist_ok=True)

# ============================================================================
# FUNCTIONGEMMA SYSTEM PROMPT AND HELPERS
# ============================================================================

FUNCTIONGEMMA_SYSTEM_PROMPT = """You are FunctionGemma, the CosmoOS Micro-Brain. You interpret user voice commands and output exactly ONE function call.
You NEVER reason, explain, or generate text. You ONLY output function calls in the format:
<start_function_call>call:FUNCTION_NAME{params}<end_function_call>

Available functions: create_atom, update_atom, delete_atom, search_atoms, batch_create, navigate, query_level_system, start_deep_work, stop_deep_work, extend_deep_work, log_workout, trigger_correlation_analysis"""


def escape(value):
    """Escape a value for FunctionGemma output format."""
    if isinstance(value, dict):
        return json.dumps(value, separators=(',', ':'))
    elif isinstance(value, list):
        return json.dumps(value, separators=(',', ':'))
    elif isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, (int, float)):
        return str(value)
    else:
        return str(value)


def make_function_call(func_name: str, params: dict) -> str:
    """Generate FunctionGemma output format string."""
    param_parts = []
    for key, value in params.items():
        param_parts.append(f"{key}:<escape>{escape(value)}<escape>")
    params_str = ",".join(param_parts)
    return f"<start_function_call>call:{func_name}{{{params_str}}}<end_function_call>"

# ============================================================================
# DATA BANKS - Rich vocabulary for diverse training examples
# ============================================================================

# Topics for ideas
TOPICS = [
    # Business & Marketing
    "marketing strategy", "brand positioning", "customer acquisition", "retention metrics",
    "social media campaign", "content marketing", "SEO optimization", "email automation",
    "lead generation", "conversion funnel", "A/B testing", "user personas",
    "competitive analysis", "market research", "pricing strategy", "product launch",

    # Product & Engineering
    "feature architecture", "API design", "database schema", "caching strategy",
    "performance optimization", "code refactoring", "technical debt", "microservices",
    "authentication flow", "authorization patterns", "error handling", "logging strategy",
    "CI/CD pipeline", "deployment automation", "monitoring setup", "incident response",
    "mobile optimization", "offline support", "data migration", "versioning strategy",

    # Design & UX
    "user onboarding", "navigation patterns", "color scheme", "typography system",
    "component library", "design tokens", "accessibility improvements", "mobile UX",
    "dark mode implementation", "animation principles", "icon system", "layout grid",
    "form validation UX", "error messaging", "loading states", "empty states",

    # Growth & Strategy
    "growth hacking", "viral loops", "referral program", "partnership strategy",
    "investor pitch", "fundraising deck", "unit economics", "market expansion",
    "international launch", "localization", "pricing tiers", "freemium model",

    # Personal Development
    "learning roadmap", "skill development", "reading list", "networking strategy",
    "time management", "productivity system", "habit formation", "goal setting",
    "morning routine", "evening routine", "meditation practice", "exercise plan",

    # Content & Writing
    "blog post series", "newsletter topics", "podcast episodes", "video content",
    "case studies", "whitepapers", "documentation", "help articles",
    "social posts", "ad copy", "landing pages", "email sequences",

    # Research
    "user research", "market trends", "competitor analysis", "technology evaluation",
    "framework comparison", "best practices", "industry benchmarks", "case study analysis",
]

# Tasks for to-dos
TASKS = [
    # Communication
    "call mom", "call dad", "call Sarah", "call John", "call the dentist",
    "email the team", "email investors", "email marketing", "email support",
    "text Alex", "text the group", "message the client", "follow up with leads",
    "schedule meeting with product", "book 1:1 with manager", "set up call with design",

    # Work Tasks
    "finish the report", "review the PR", "update documentation", "fix the bug",
    "write tests", "deploy to staging", "merge the feature branch", "update dependencies",
    "create the presentation", "prepare for standup", "update the roadmap", "write specs",
    "review analytics", "check metrics", "update dashboards", "run experiments",
    "interview candidates", "review applications", "prepare interview questions",

    # Personal
    "buy groceries", "pick up laundry", "return package", "pay bills",
    "renew subscription", "cancel gym membership", "book dentist", "schedule haircut",
    "water plants", "clean apartment", "do laundry", "cook dinner",
    "exercise", "meditate", "read for 30 minutes", "practice Spanish",
    "take vitamins", "drink water", "go for a walk", "stretch",

    # Shopping
    "order supplies", "buy birthday gift", "get flowers", "pick up prescription",
    "return shoes", "exchange jacket", "order office supplies", "buy charger",

    # Errands
    "drop off mail", "go to bank", "visit post office", "get car serviced",
    "renew license", "update passport", "file taxes", "submit expense report",
]

# Standard project names (generic)
PROJECTS = [
    "marketing", "product", "engineering", "design", "sales", "operations",
    "personal", "health", "finance", "learning", "side project", "home",
    "q1 goals", "q2 planning", "annual review", "strategic initiative",
    "app redesign", "backend migration", "mobile app", "web platform",
    "customer success", "support", "content", "growth", "partnerships",
]

# Person names (for "idea for Michael" type commands) - CRITICAL for project inbox
PERSON_NAMES = [
    # Common first names
    "Michael", "Sarah", "John", "Emily", "David", "Lisa", "James", "Jennifer",
    "Robert", "Jessica", "William", "Ashley", "Christopher", "Amanda", "Daniel",
    "Nicole", "Matthew", "Stephanie", "Anthony", "Melissa", "Mark", "Michelle",
    "Andrew", "Elizabeth", "Joshua", "Kimberly", "Steven", "Rebecca", "Kevin",
    "Laura", "Brian", "Rachel", "Alex", "Chris", "Sam", "Jordan", "Taylor",
    "Morgan", "Casey", "Jamie", "Cameron", "Drew", "Pat", "Quinn", "Riley",
    # Business/Professional
    "Dr. Smith", "Dr. Johnson", "Professor Lee", "Coach Williams",
]

# Company/Client names (for business contexts)
COMPANY_NAMES = [
    "Acme", "TechCorp", "GlobalSoft", "Innovate Inc", "StartupX", "ClientCo",
    "PartnerGroup", "VentureOne", "CloudNine", "DataDriven", "NextGen",
    "BlueChip", "GreenLeaf", "RedRock", "SilverLine", "GoldStar",
]

# Combined project references (person, company, or generic project)
def get_project_references():
    """Get all possible project references with their types."""
    refs = []
    # Person names are most natural for "idea for X"
    refs.extend([(name, "person") for name in PERSON_NAMES])
    # Companies
    refs.extend([(name, "company") for name in COMPANY_NAMES])
    # Generic projects
    refs.extend([(name, "project") for name in PROJECTS])
    return refs

PROJECT_REFERENCES = get_project_references()

# Time expressions
TIMES = [
    "9am", "10am", "11am", "12pm", "1pm", "2pm", "3pm", "4pm", "5pm", "6pm",
    "9", "10", "11", "12", "1", "2", "3", "4", "5", "6",
    "9:30", "10:30", "11:30", "12:30", "1:30", "2:30", "3:30", "4:30",
    "morning", "afternoon", "evening", "noon", "end of day", "close of business",
]

RELATIVE_TIMES = [
    "tomorrow", "next week", "next Monday", "next Tuesday", "next Wednesday",
    "this Friday", "this weekend", "in an hour", "in 2 hours", "in 30 minutes",
    "later today", "tonight", "this evening", "next month", "end of week",
]

DURATIONS = [
    ("30 minutes", 30), ("1 hour", 60), ("1.5 hours", 90), ("2 hours", 120),
    ("45 minutes", 45), ("15 minutes", 15), ("3 hours", 180), ("half hour", 30),
    ("an hour", 60), ("couple hours", 120),
]

# Priorities
PRIORITIES = ["low", "medium", "high"]
PRIORITY_PHRASES = {
    "low": ["low priority", "not urgent", "when I get to it", "optional"],
    "medium": ["medium priority", "normal priority", "regular", "standard"],
    "high": ["high priority", "urgent", "important", "critical", "asap", "right away"],
}

# Block types
BLOCK_TYPES = [
    ("focus", ["deep work", "focused time", "heads down", "no meetings", "concentration time"]),
    ("task", ["work block", "task time", "working on", "getting things done"]),
    ("event", ["meeting", "call", "sync", "standup", "review", "interview", "lunch", "coffee"]),
]

# Modification actions
STATUS_CHANGES = [
    ("completed", ["mark as complete", "mark as done", "done", "finished", "complete this", "check off"]),
    ("in_progress", ["start working on", "in progress", "working on it", "started"]),
    ("todo", ["put back to todo", "reopen", "undo complete", "not done yet"]),
]

# ============================================================================
# TEMPLATE GENERATORS
# ============================================================================

def generate_simple_creation_examples(n=3500):
    """Generate simple entity creation examples (no time expressions, no project)."""
    examples = []

    # Idea creation templates
    idea_templates = [
        ("Create idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("New idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Add idea for {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Jot down idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Note about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("I have an idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Thought about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Add thought on {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Capture idea for {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Quick idea {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Idea {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("{topic} idea", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Brain dump about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Let me note down {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
        ("Save idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}"}),
    ]

    # Task creation templates
    task_templates = [
        ("Create task {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("New task {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Add task {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("I need to {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Remind me to {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Don't let me forget to {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Add to my list {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Todo {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("To do {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("{task}", {"action": "create", "type": "task", "title": "{task}"}),  # Bare command
        ("Make sure I {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Put on my list {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Add {task} to tasks", {"action": "create", "type": "task", "title": "{task}"}),
        ("Task to {task}", {"action": "create", "type": "task", "title": "{task}"}),
        ("Need to {task}", {"action": "create", "type": "task", "title": "{task}"}),
    ]

    # Project creation templates
    project_templates = [
        ("Create project called {project}", {"action": "create", "type": "project", "title": "{project}"}),
        ("New project {project}", {"action": "create", "type": "project", "title": "{project}"}),
        ("Start a project for {project}", {"action": "create", "type": "project", "title": "{project}"}),
        ("Add project {project}", {"action": "create", "type": "project", "title": "{project}"}),
    ]

    # Research creation templates
    research_templates = [
        ("Save this article about {topic}", {"action": "create", "type": "research", "title": "{topic}"}),
        ("Add to research {topic}", {"action": "create", "type": "research", "title": "{topic}"}),
        ("Research about {topic}", {"action": "create", "type": "research", "title": "{topic}"}),
        ("Look into {topic}", {"action": "create", "type": "research", "title": "{topic}"}),
        ("Investigate {topic}", {"action": "create", "type": "research", "title": "{topic}"}),
    ]

    # Note creation templates (floating blocks in Thinkspace)
    note_templates = [
        ("Create note about {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
        ("New note {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
        ("Add note about {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
        ("Quick note {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
        ("Note {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
        ("Floating note {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
        ("Add floating note about {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
        ("Drop a note about {topic}", {"action": "create", "type": "note", "title": "{topic}"}),
    ]

    # Thinkspace creation templates (saved canvas configurations)
    thinkspace_templates = [
        ("Create thinkspace for {topic}", {"action": "create", "type": "thinkspace", "title": "{topic}"}),
        ("New thinkspace {topic}", {"action": "create", "type": "thinkspace", "title": "{topic}"}),
        ("Add thinkspace about {topic}", {"action": "create", "type": "thinkspace", "title": "{topic}"}),
        ("Create canvas for {topic}", {"action": "create", "type": "thinkspace", "title": "{topic}"}),
        ("New canvas {topic}", {"action": "create", "type": "thinkspace", "title": "{topic}"}),
        ("Start a thinkspace for {topic}", {"action": "create", "type": "thinkspace", "title": "{topic}"}),
        ("Make a thinking space for {topic}", {"action": "create", "type": "thinkspace", "title": "{topic}"}),
    ]

    # Connection creation templates (mental models)
    connection_templates = [
        ("Create connection about {topic}", {"action": "create", "type": "connection", "title": "{topic}"}),
        ("New connection {topic}", {"action": "create", "type": "connection", "title": "{topic}"}),
        ("Add connection for {topic}", {"action": "create", "type": "connection", "title": "{topic}"}),
        ("Mental model for {topic}", {"action": "create", "type": "connection", "title": "{topic}"}),
        ("Create mental model about {topic}", {"action": "create", "type": "connection", "title": "{topic}"}),
        ("Link {topic}", {"action": "create", "type": "connection", "title": "{topic}"}),
        ("Connect {topic}", {"action": "create", "type": "connection", "title": "{topic}"}),
    ]

    # Idea creation with priority
    idea_priority_templates = [
        ("Create {priority} priority idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}", "metadata": {"priority": "{priority}"}}),
        ("High priority idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}", "metadata": {"priority": "high"}}),
        ("Important idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}", "metadata": {"priority": "high"}}),
    ]

    # Task creation with priority
    task_priority_templates = [
        ("Urgent task {task}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"priority": "high"}}),
        ("High priority {task}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"priority": "high"}}),
        ("Low priority {task}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"priority": "low"}}),
        ("Important {task}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"priority": "high"}}),
        ("When I get to it {task}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"priority": "low"}}),
    ]

    # Distribute examples across templates
    all_templates = (
        idea_templates * 3 +  # More weight on ideas
        task_templates * 4 +  # Most weight on tasks
        project_templates +
        research_templates +
        note_templates * 2 +  # Floating notes are common
        thinkspace_templates +  # Canvas/thinkspace creation
        connection_templates +  # Mental models
        idea_priority_templates +
        task_priority_templates
    )

    for _ in range(n):
        template, output_template = random.choice(all_templates)
        topic = random.choice(TOPICS)
        task = random.choice(TASKS)
        project = random.choice(PROJECTS)
        priority = random.choice(PRIORITIES)

        input_text = template.format(topic=topic, task=task, project=project, priority=priority)

        # Deep copy and substitute
        output_str = json.dumps(output_template)
        output_str = output_str.replace("{topic}", topic)
        output_str = output_str.replace("{task}", task)
        output_str = output_str.replace("{project}", project)
        output_str = output_str.replace("{priority}", priority)
        output = json.loads(output_str)

        examples.append({"input": input_text, "output": output})

    return examples


def generate_project_specific_examples(n=2500):
    """
    Generate project-specific entity creation examples.
    This is CRITICAL for commands like:
    - "Idea for Michael about user onboarding"
    - "I just had this thought for Sarah"
    - "Task for marketing project"
    - "Add to Acme inbox"
    """
    examples = []

    # ==================== IDEA FOR [PROJECT] ====================
    # These are the most common - someone capturing an idea for a specific person/project

    idea_for_project_templates = [
        # "Idea for X" pattern (most natural)
        ("Idea for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Idea for {project_ref} about {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Idea for {project_ref}: {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "New idea for X"
        ("New idea for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("New idea for {project_ref} about {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "I just got/had this idea for X"
        ("I just got this idea for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("I just had this idea for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Just got an idea for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Just had a thought for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "Thought for X"
        ("Thought for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Quick thought for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "Note for X"
        ("Note for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Add note for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "Add to X"
        ("Add to {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Add to {project_ref} inbox {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Put in {project_ref} inbox {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "For X" at the start
        ("For {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("For {project_ref} idea about {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # With "project" suffix
        ("Idea for {project_ref} project {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Add idea to {project_ref} project {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # Capture/save patterns
        ("Capture for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Save for {project_ref} {topic}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
    ]

    # ==================== TASK FOR [PROJECT] ====================

    task_for_project_templates = [
        # "Task for X"
        ("Task for {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("New task for {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Add task for {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "Task to X for Y"
        ("Add task to {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Create task in {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "For X" at start
        ("For {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("For {project_ref} task to {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "I need to X for Y"
        ("I need to {task} for {project_ref}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Need to {task} for {project_ref}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # "Remind me for X"
        ("Remind me for {project_ref} to {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # With "project" suffix
        ("Task for {project_ref} project {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("{task} for {project_ref} project", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),

        # Todo patterns
        ("Todo for {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("To do for {project_ref} {task}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
    ]

    # ==================== RESEARCH FOR [PROJECT] ====================

    research_for_project_templates = [
        ("Research for {project_ref} {topic}", {"action": "create", "type": "research", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Add research for {project_ref} about {topic}", {"action": "create", "type": "research", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Save for {project_ref} research {topic}", {"action": "create", "type": "research", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
    ]

    # ==================== IDEA/TASK ENDING WITH "FOR X" ====================

    # This pattern: "{content} for {project}"
    ending_with_for_templates = [
        ("{topic} idea for {project_ref}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Idea about {topic} for {project_ref}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("New idea about {topic} for {project_ref}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Thought about {topic} for {project_ref}", {"action": "create", "type": "idea", "title": "{topic}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("{task} for {project_ref}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Task {task} for {project_ref}", {"action": "create", "type": "task", "title": "{task}", "links": [{"type": "project", "query": "{project_ref}"}]}),
    ]

    # Combine all templates with appropriate weights
    all_templates = (
        idea_for_project_templates * 4 +  # Heavy weight on "idea for X" pattern
        task_for_project_templates * 3 +
        research_for_project_templates +
        ending_with_for_templates * 2
    )

    for _ in range(n):
        template, output_template = random.choice(all_templates)

        # Select project reference (person name, company, or generic project)
        project_ref, ref_type = random.choice(PROJECT_REFERENCES)
        topic = random.choice(TOPICS)
        task = random.choice(TASKS)

        input_text = template.format(project_ref=project_ref, topic=topic, task=task)

        # Deep copy and substitute
        output_str = json.dumps(output_template)
        output_str = output_str.replace("{project_ref}", project_ref)
        output_str = output_str.replace("{topic}", topic)
        output_str = output_str.replace("{task}", task)
        output = json.loads(output_str)

        examples.append({"input": input_text, "output": output})

    return examples


def generate_timed_creation_examples(n=2000):
    """Generate entity creation examples with time expressions."""
    examples = []

    # Task with absolute time
    timed_task_templates = [
        ("Task {task} at {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}}),
        ("{task} at {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}}),
        ("Remind me to {task} at {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}}),
        ("Schedule {task} for {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}}),
        ("{task} scheduled for {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}}),
        ("Put {task} at {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}}),
    ]

    # Task with relative time
    relative_task_templates = [
        ("{task} {relative_time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{relative_time}"}}),
        ("Remind me {relative_time} to {task}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{relative_time}"}}),
        ("Schedule {task} for {relative_time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{relative_time}"}}),
        ("{relative_time} {task}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{relative_time}"}}),
    ]

    # Schedule block with time range
    block_range_templates = [
        ("Block {start_time} to {end_time} for {block_name}", {"action": "create", "type": "schedule_block", "title": "{block_name}", "metadata": {"startTime": "{start_time}", "endTime": "{end_time}", "blockType": "focus"}}),
        ("Deep work from {start_time} to {end_time}", {"action": "create", "type": "schedule_block", "title": "Deep work", "metadata": {"startTime": "{start_time}", "endTime": "{end_time}", "blockType": "focus"}}),
        ("Focus time {start_time} to {end_time}", {"action": "create", "type": "schedule_block", "title": "Focus time", "metadata": {"startTime": "{start_time}", "endTime": "{end_time}", "blockType": "focus"}}),
        ("Meeting from {start_time} to {end_time} {block_name}", {"action": "create", "type": "schedule_block", "title": "{block_name}", "metadata": {"startTime": "{start_time}", "endTime": "{end_time}", "blockType": "event"}}),
        ("{block_name} from {start_time} to {end_time}", {"action": "create", "type": "schedule_block", "title": "{block_name}", "metadata": {"startTime": "{start_time}", "endTime": "{end_time}", "blockType": "task"}}),
    ]

    # Schedule block with duration
    block_duration_templates = [
        ("Block {duration} for {block_name} at {time}", {"action": "create", "type": "schedule_block", "title": "{block_name}", "metadata": {"startTime": "{time}", "duration": "{duration}", "blockType": "task"}}),
        ("{duration} of {block_name} at {time}", {"action": "create", "type": "schedule_block", "title": "{block_name}", "metadata": {"startTime": "{time}", "duration": "{duration}", "blockType": "task"}}),
        ("Schedule {duration} for {block_name}", {"action": "create", "type": "schedule_block", "title": "{block_name}", "metadata": {"duration": "{duration}", "blockType": "task"}}),
    ]

    # Meeting templates
    meeting_templates = [
        ("Meeting with {person} at {time}", {"action": "create", "type": "schedule_block", "title": "Meeting with {person}", "metadata": {"startTime": "{time}", "blockType": "event"}}),
        ("Call with {person} at {time}", {"action": "create", "type": "schedule_block", "title": "Call with {person}", "metadata": {"startTime": "{time}", "blockType": "event"}}),
        ("1:1 with {person} at {time}", {"action": "create", "type": "schedule_block", "title": "1:1 with {person}", "metadata": {"startTime": "{time}", "blockType": "event"}}),
        ("Sync with {person} {relative_time}", {"action": "create", "type": "schedule_block", "title": "Sync with {person}", "metadata": {"startTime": "{relative_time}", "blockType": "event"}}),
    ]

    # Timed task FOR PROJECT
    timed_task_project_templates = [
        ("Task for {project_ref} {task} at {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}, "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("{task} for {project_ref} at {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}, "links": [{"type": "project", "query": "{project_ref}"}]}),
        ("Remind me for {project_ref} to {task} at {time}", {"action": "create", "type": "task", "title": "{task}", "metadata": {"startTime": "{time}"}, "links": [{"type": "project", "query": "{project_ref}"}]}),
    ]

    people = ["John", "Sarah", "Alex", "Mike", "Lisa", "David", "Emily", "Chris", "Rachel", "Tom", "the team", "marketing", "design", "engineering", "product"]

    block_names = ["deep work", "focused coding", "writing time", "review session", "planning", "research", "reading", "admin tasks", "emails", "brainstorming"]

    hours = list(range(8, 18))  # 8am to 5pm

    for _ in range(n):
        template_type = random.choice(["timed_task", "relative_task", "block_range", "block_duration", "meeting", "timed_project"])

        if template_type == "timed_task":
            template, output_template = random.choice(timed_task_templates)
            task = random.choice(TASKS)
            time = random.choice(TIMES)
            input_text = template.format(task=task, time=time)
            output_str = json.dumps(output_template).replace("{task}", task).replace("{time}", time)

        elif template_type == "relative_task":
            template, output_template = random.choice(relative_task_templates)
            task = random.choice(TASKS)
            relative_time = random.choice(RELATIVE_TIMES)
            input_text = template.format(task=task, relative_time=relative_time)
            output_str = json.dumps(output_template).replace("{task}", task).replace("{relative_time}", relative_time)

        elif template_type == "block_range":
            template, output_template = random.choice(block_range_templates)
            start_hour = random.choice(hours[:-2])
            end_hour = start_hour + random.choice([1, 2, 3])
            start_time = f"{start_hour}{'pm' if start_hour >= 12 else 'am'}"
            end_time = f"{end_hour}{'pm' if end_hour >= 12 else 'am'}"
            block_name = random.choice(block_names)
            input_text = template.format(start_time=start_time, end_time=end_time, block_name=block_name)
            output_str = json.dumps(output_template).replace("{start_time}", start_time).replace("{end_time}", end_time).replace("{block_name}", block_name)

        elif template_type == "block_duration":
            template, output_template = random.choice(block_duration_templates)
            duration, _ = random.choice(DURATIONS)
            block_name = random.choice(block_names)
            time = random.choice(TIMES)
            input_text = template.format(duration=duration, block_name=block_name, time=time)
            output_str = json.dumps(output_template).replace("{duration}", duration).replace("{block_name}", block_name).replace("{time}", time)

        elif template_type == "timed_project":
            template, output_template = random.choice(timed_task_project_templates)
            task = random.choice(TASKS)
            time = random.choice(TIMES)
            project_ref, _ = random.choice(PROJECT_REFERENCES)
            input_text = template.format(task=task, time=time, project_ref=project_ref)
            output_str = json.dumps(output_template).replace("{task}", task).replace("{time}", time).replace("{project_ref}", project_ref)

        else:  # meeting
            template, output_template = random.choice(meeting_templates)
            person = random.choice(people)
            time = random.choice(TIMES)
            relative_time = random.choice(RELATIVE_TIMES)
            input_text = template.format(person=person, time=time, relative_time=relative_time)
            output_str = json.dumps(output_template).replace("{person}", person).replace("{time}", time).replace("{relative_time}", relative_time)

        output = json.loads(output_str)
        examples.append({"input": input_text, "output": output})

    return examples


def generate_modification_examples(n=1500):
    """Generate entity modification examples."""
    examples = []

    # Status changes
    status_templates = [
        ("Mark as complete", {"action": "update", "target": "context", "metadata": {"status": "completed"}}),
        ("Done", {"action": "update", "target": "context", "metadata": {"status": "completed"}}),
        ("Complete", {"action": "update", "target": "context", "metadata": {"status": "completed"}}),
        ("Finish this", {"action": "update", "target": "context", "metadata": {"status": "completed"}}),
        ("Check this off", {"action": "update", "target": "context", "metadata": {"status": "completed"}}),
        ("I finished this", {"action": "update", "target": "context", "metadata": {"status": "completed"}}),
        ("That's done", {"action": "update", "target": "context", "metadata": {"status": "completed"}}),
        ("Mark in progress", {"action": "update", "target": "context", "metadata": {"status": "in_progress"}}),
        ("Start working on this", {"action": "update", "target": "context", "metadata": {"status": "in_progress"}}),
        ("Working on it", {"action": "update", "target": "context", "metadata": {"status": "in_progress"}}),
        ("Reopen this", {"action": "update", "target": "context", "metadata": {"status": "todo"}}),
        ("Not done yet", {"action": "update", "target": "context", "metadata": {"status": "todo"}}),
        ("Undo complete", {"action": "update", "target": "context", "metadata": {"status": "todo"}}),
    ]

    # Time modifications
    time_templates = [
        ("Move to {time}", {"action": "update", "target": "context", "metadata": {"startTime": "{time}"}}),
        ("Reschedule to {time}", {"action": "update", "target": "context", "metadata": {"startTime": "{time}"}}),
        ("Push to {time}", {"action": "update", "target": "context", "metadata": {"startTime": "{time}"}}),
        ("Change time to {time}", {"action": "update", "target": "context", "metadata": {"startTime": "{time}"}}),
        ("Move this to {relative_time}", {"action": "update", "target": "context", "metadata": {"startTime": "{relative_time}"}}),
        ("Delay to {relative_time}", {"action": "update", "target": "context", "metadata": {"startTime": "{relative_time}"}}),
        ("Extend to {time}", {"action": "update", "target": "context", "metadata": {"endTime": "{time}"}}),
        ("End at {time}", {"action": "update", "target": "context", "metadata": {"endTime": "{time}"}}),
        ("Make it end at {time}", {"action": "update", "target": "context", "metadata": {"endTime": "{time}"}}),
    ]

    # Priority modifications
    priority_templates = [
        ("Make this high priority", {"action": "update", "target": "context", "metadata": {"priority": "high"}}),
        ("High priority", {"action": "update", "target": "context", "metadata": {"priority": "high"}}),
        ("This is urgent", {"action": "update", "target": "context", "metadata": {"priority": "high"}}),
        ("Important", {"action": "update", "target": "context", "metadata": {"priority": "high"}}),
        ("Lower the priority", {"action": "update", "target": "context", "metadata": {"priority": "low"}}),
        ("Low priority", {"action": "update", "target": "context", "metadata": {"priority": "low"}}),
        ("Not that important", {"action": "update", "target": "context", "metadata": {"priority": "low"}}),
        ("Normal priority", {"action": "update", "target": "context", "metadata": {"priority": "medium"}}),
        ("Medium priority", {"action": "update", "target": "context", "metadata": {"priority": "medium"}}),
    ]

    # Project assignment
    project_templates = [
        ("Add to {project} project", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{project}"}]}),
        ("Move to {project}", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{project}"}]}),
        ("Put this in {project}", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{project}"}]}),
        ("Assign to {project}", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{project}"}]}),
        ("This belongs in {project}", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{project}"}]}),
        # Person-specific project assignment
        ("Add to {person_name}", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{person_name}"}]}),
        ("Move to {person_name}", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{person_name}"}]}),
        ("Put in {person_name} inbox", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{person_name}"}]}),
        ("Send to {person_name}", {"action": "update", "target": "context", "links": [{"type": "project", "query": "{person_name}"}]}),
    ]

    # Title/content modifications
    content_templates = [
        ("Rename to {task}", {"action": "update", "target": "context", "title": "{task}"}),
        ("Change title to {task}", {"action": "update", "target": "context", "title": "{task}"}),
        ("Call it {task} instead", {"action": "update", "target": "context", "title": "{task}"}),
        ("Actually make it {task}", {"action": "update", "target": "context", "title": "{task}"}),
    ]

    # Delete templates
    delete_templates = [
        ("Delete this", {"action": "delete", "target": "context"}),
        ("Remove this", {"action": "delete", "target": "context"}),
        ("Delete that", {"action": "delete", "target": "context"}),
        ("Get rid of this", {"action": "delete", "target": "context"}),
        ("Remove it", {"action": "delete", "target": "context"}),
        ("Cancel this", {"action": "delete", "target": "context"}),
        ("Never mind", {"action": "delete", "target": "context"}),
    ]

    all_templates = (
        status_templates * 3 +
        time_templates * 2 +
        priority_templates * 2 +
        project_templates * 3 +  # Increased weight for project assignment
        content_templates +
        delete_templates * 2
    )

    for _ in range(n):
        template, output_template = random.choice(all_templates)
        time = random.choice(TIMES)
        relative_time = random.choice(RELATIVE_TIMES)
        project = random.choice(PROJECTS)
        person_name = random.choice(PERSON_NAMES)
        task = random.choice(TASKS)

        input_text = template.format(time=time, relative_time=relative_time, project=project, task=task, person_name=person_name)
        output_str = json.dumps(output_template)
        output_str = output_str.replace("{time}", time)
        output_str = output_str.replace("{relative_time}", relative_time)
        output_str = output_str.replace("{project}", project)
        output_str = output_str.replace("{person_name}", person_name)
        output_str = output_str.replace("{task}", task)
        output = json.loads(output_str)

        examples.append({"input": input_text, "output": output})

    return examples


def generate_search_examples(n=1500):
    """Generate search and retrieval examples."""
    examples = []

    # Type-filtered search
    type_search_templates = [
        ("Find ideas about {query}", {"action": "search", "type": "idea", "query": "{query}"}),
        ("Show ideas about {query}", {"action": "search", "type": "idea", "query": "{query}"}),
        ("Search ideas for {query}", {"action": "search", "type": "idea", "query": "{query}"}),
        ("What ideas do I have about {query}", {"action": "search", "type": "idea", "query": "{query}"}),
        ("Find tasks about {query}", {"action": "search", "type": "task", "query": "{query}"}),
        ("Show tasks for {query}", {"action": "search", "type": "task", "query": "{query}"}),
        ("What tasks are related to {query}", {"action": "search", "type": "task", "query": "{query}"}),
        ("Find research on {query}", {"action": "search", "type": "research", "query": "{query}"}),
        ("Show me research about {query}", {"action": "search", "type": "research", "query": "{query}"}),
        ("What research do I have on {query}", {"action": "search", "type": "research", "query": "{query}"}),
        # Notes
        ("Find notes about {query}", {"action": "search", "type": "note", "query": "{query}"}),
        ("Show notes about {query}", {"action": "search", "type": "note", "query": "{query}"}),
        ("Search notes for {query}", {"action": "search", "type": "note", "query": "{query}"}),
        ("What notes do I have about {query}", {"action": "search", "type": "note", "query": "{query}"}),
        # Thinkspaces
        ("Find thinkspaces about {query}", {"action": "search", "type": "thinkspace", "query": "{query}"}),
        ("Show thinkspaces for {query}", {"action": "search", "type": "thinkspace", "query": "{query}"}),
        ("What canvases do I have about {query}", {"action": "search", "type": "thinkspace", "query": "{query}"}),
        # Connections
        ("Find connections about {query}", {"action": "search", "type": "connection", "query": "{query}"}),
        ("Show connections for {query}", {"action": "search", "type": "connection", "query": "{query}"}),
        ("What mental models do I have about {query}", {"action": "search", "type": "connection", "query": "{query}"}),
    ]

    # General search
    general_search_templates = [
        ("Search for {query}", {"action": "search", "query": "{query}"}),
        ("Find {query}", {"action": "search", "query": "{query}"}),
        ("Look for {query}", {"action": "search", "query": "{query}"}),
        ("What do I have about {query}", {"action": "search", "query": "{query}"}),
        ("Search {query}", {"action": "search", "query": "{query}"}),
        ("Find anything about {query}", {"action": "search", "query": "{query}"}),
    ]

    # Time-filtered search
    time_search_templates = [
        ("What tasks are due today", {"action": "search", "type": "task", "filter": {"dueDate": "today"}}),
        ("Show me today's tasks", {"action": "search", "type": "task", "filter": {"dueDate": "today"}}),
        ("What's due this week", {"action": "search", "type": "task", "filter": {"dueDate": "this week"}}),
        ("Tasks for tomorrow", {"action": "search", "type": "task", "filter": {"dueDate": "tomorrow"}}),
        ("What do I have scheduled today", {"action": "search", "type": "schedule_block", "filter": {"date": "today"}}),
        ("Show my schedule for tomorrow", {"action": "search", "type": "schedule_block", "filter": {"date": "tomorrow"}}),
    ]

    # Status-filtered search
    status_search_templates = [
        ("Show completed tasks", {"action": "search", "type": "task", "filter": {"status": "completed"}}),
        ("What have I finished", {"action": "search", "type": "task", "filter": {"status": "completed"}}),
        ("Show open tasks", {"action": "search", "type": "task", "filter": {"status": "todo"}}),
        ("What's left to do", {"action": "search", "type": "task", "filter": {"status": "todo"}}),
        ("Tasks in progress", {"action": "search", "type": "task", "filter": {"status": "in_progress"}}),
        ("What am I working on", {"action": "search", "type": "task", "filter": {"status": "in_progress"}}),
    ]

    # Project-filtered search
    project_search_templates = [
        ("Show tasks in {project}", {"action": "search", "type": "task", "filter": {"project": "{project}"}}),
        ("What's in {project} project", {"action": "search", "filter": {"project": "{project}"}}),
        ("Ideas for {project}", {"action": "search", "type": "idea", "filter": {"project": "{project}"}}),
        ("Everything in {project}", {"action": "search", "filter": {"project": "{project}"}}),
        # Person-specific project search
        ("Show ideas for {person_name}", {"action": "search", "type": "idea", "filter": {"project": "{person_name}"}}),
        ("What's in {person_name}", {"action": "search", "filter": {"project": "{person_name}"}}),
        ("Tasks for {person_name}", {"action": "search", "type": "task", "filter": {"project": "{person_name}"}}),
        ("{person_name} inbox", {"action": "search", "filter": {"project": "{person_name}"}}),
        ("Show {person_name} project", {"action": "search", "filter": {"project": "{person_name}"}}),
    ]

    # Semantic search
    semantic_templates = [
        ("What's relevant to this", {"action": "search", "target": "context", "mode": "semantic"}),
        ("Find related items", {"action": "search", "target": "context", "mode": "semantic"}),
        ("Show similar things", {"action": "search", "target": "context", "mode": "semantic"}),
        ("What connects to this", {"action": "search", "target": "context", "mode": "semantic"}),
    ]

    # Navigation (special type of search)
    navigation_templates = [
        ("Open projects", {"action": "navigate", "destination": "projects"}),
        ("Go to ideas", {"action": "navigate", "destination": "ideas"}),
        ("Show me tasks", {"action": "navigate", "destination": "tasks"}),
        ("Open today", {"action": "navigate", "destination": "today"}),
        ("Go to schedule", {"action": "navigate", "destination": "schedule"}),
        ("Show research", {"action": "navigate", "destination": "research"}),
        ("Open settings", {"action": "navigate", "destination": "settings"}),
        ("Go home", {"action": "navigate", "destination": "home"}),
        # NEW: Modern navigation destinations
        ("Open plannerum", {"action": "navigate", "destination": "plannerum"}),
        ("Go to planner", {"action": "navigate", "destination": "plannerum"}),
        ("Show planner", {"action": "navigate", "destination": "plannerum"}),
        ("Open thinkspace", {"action": "navigate", "destination": "thinkspace"}),
        ("Go to canvas", {"action": "navigate", "destination": "thinkspace"}),
        ("Show canvas", {"action": "navigate", "destination": "thinkspace"}),
        ("Open inbox", {"action": "navigate", "destination": "inbox"}),
        ("Go to inbox", {"action": "navigate", "destination": "inbox"}),
        ("Open notes", {"action": "navigate", "destination": "notes"}),
        ("Go to notes", {"action": "navigate", "destination": "notes"}),
    ]

    all_templates = (
        type_search_templates * 3 +
        general_search_templates * 3 +
        time_search_templates * 2 +
        status_search_templates * 2 +
        project_search_templates * 3 +  # Increased weight
        semantic_templates +
        navigation_templates * 2
    )

    search_queries = TOPICS + list(set([t.split()[-1] for t in TASKS]))  # Topics + last word of tasks

    for _ in range(n):
        template, output_template = random.choice(all_templates)
        query = random.choice(search_queries)
        project = random.choice(PROJECTS)
        person_name = random.choice(PERSON_NAMES)

        input_text = template.format(query=query, project=project, person_name=person_name)
        output_str = json.dumps(output_template)
        output_str = output_str.replace("{query}", query)
        output_str = output_str.replace("{project}", project)
        output_str = output_str.replace("{person_name}", person_name)
        output = json.loads(output_str)

        examples.append({"input": input_text, "output": output})

    return examples


def generate_batch_examples(n=1000):
    """Generate multi-entity / brain dump examples."""
    examples = []

    # Two-item batches
    two_item_templates = [
        ("I need to {task1} and {task2}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}]}),
        ("{task1} and {task2}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}]}),
        ("Create tasks {task1} and {task2}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}]}),
        ("Add {task1} and also {task2}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}]}),
    ]

    # Three-item batches
    three_item_templates = [
        ("I need to {task1}, {task2}, and {task3}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}, {"type": "task", "title": "{task3}"}]}),
        ("{task1}, {task2}, and {task3}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}, {"type": "task", "title": "{task3}"}]}),
        ("Create tasks for {task1}, {task2}, and {task3}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}, {"type": "task", "title": "{task3}"}]}),
        ("Add to my list {task1}, {task2}, {task3}", {"action": "batch", "items": [{"type": "task", "title": "{task1}"}, {"type": "task", "title": "{task2}"}, {"type": "task", "title": "{task3}"}]}),
    ]

    # Mixed type batches
    mixed_templates = [
        ("Idea about {topic} and task to {task1}", {"action": "batch", "items": [{"type": "idea", "title": "{topic}"}, {"type": "task", "title": "{task1}"}]}),
        ("Note about {topic} and remind me to {task1}", {"action": "batch", "items": [{"type": "idea", "title": "{topic}"}, {"type": "task", "title": "{task1}"}]}),
    ]

    # Batch FOR PROJECT
    batch_project_templates = [
        ("For {project_ref} {task1} and {task2}", {"action": "batch", "items": [{"type": "task", "title": "{task1}", "links": [{"type": "project", "query": "{project_ref}"}]}, {"type": "task", "title": "{task2}", "links": [{"type": "project", "query": "{project_ref}"}]}]}),
        ("Add to {project_ref} {task1} and {task2}", {"action": "batch", "items": [{"type": "task", "title": "{task1}", "links": [{"type": "project", "query": "{project_ref}"}]}, {"type": "task", "title": "{task2}", "links": [{"type": "project", "query": "{project_ref}"}]}]}),
    ]

    all_templates = two_item_templates * 3 + three_item_templates * 2 + mixed_templates + batch_project_templates * 2

    for _ in range(n):
        template, output_template = random.choice(all_templates)
        tasks = random.sample(TASKS, 3)
        topic = random.choice(TOPICS)
        project_ref, _ = random.choice(PROJECT_REFERENCES)

        input_text = template.format(
            task1=tasks[0],
            task2=tasks[1],
            task3=tasks[2] if "{task3}" in template else "",
            topic=topic,
            project_ref=project_ref
        )
        output_str = json.dumps(output_template)
        output_str = output_str.replace("{task1}", tasks[0])
        output_str = output_str.replace("{task2}", tasks[1])
        output_str = output_str.replace("{task3}", tasks[2])
        output_str = output_str.replace("{topic}", topic)
        output_str = output_str.replace("{project_ref}", project_ref)
        output = json.loads(output_str)

        examples.append({"input": input_text, "output": output})

    return examples


# ============================================================================
# NEW GENERATORS FOR FUNCTIONGEMMA
# ============================================================================

# Level System Query Types
LEVEL_QUERY_TYPES = [
    ("levelStatus", ["What's my level", "What level am I", "Show my level", "Level status", "My current level"]),
    ("xpToday", ["How much XP today", "XP earned today", "Today's XP", "Show XP today", "What XP did I get"]),
    ("xpBreakdown", ["XP breakdown", "Show XP by dimension", "Break down my XP", "XP details"]),
    ("dimensionStatus", ["How's my cognitive dimension", "Show creative status", "What's my physiological progress", "Knowledge dimension status"]),
    ("streakStatus", ["What's my streak", "How long is my streak", "Current streak", "Show my streak", "Am I on a streak"]),
    ("allStreaks", ["Show all streaks", "What streaks do I have", "All my streaks", "Streak summary"]),
    ("badgesEarned", ["What badges have I earned", "Show my badges", "My achievements", "Badges unlocked", "Show achievements"]),
    ("badgeProgress", ["Badge progress", "How close am I to badges", "Which badges am I close to", "Upcoming badges"]),
    ("activeQuests", ["What quests are active", "Show my quests", "Active quests", "Current quests"]),
    ("questProgress", ["Quest progress", "How are my quests going", "Quest status"]),
    ("readinessScore", ["What's my readiness", "Am I ready to work", "Readiness score", "How ready am I"]),
    ("hrvStatus", ["What's my HRV", "Heart rate variability", "HRV status", "How's my HRV"]),
    ("sleepScore", ["How did I sleep", "Sleep score", "Sleep quality", "How was my sleep", "Last night's sleep"]),
    ("todayHealth", ["Today's health", "Health metrics", "How healthy am I today", "Vitals today"]),
    ("dailySummary", ["Daily summary", "How was my day", "Today's summary", "Summarize today"]),
    ("weeklySummary", ["Weekly summary", "How was my week", "This week's summary", "Week review"]),
    ("contentPerformance", ["How's my content doing", "Content performance", "Content stats", "Post performance"]),
    ("totalReach", ["What's my total reach", "How many people have I reached", "Reach metrics", "Content reach"]),
    ("viralCount", ["How many viral posts", "Viral content", "Which posts went viral", "Viral count"]),
    ("pipelineStatus", ["Content pipeline status", "What's in the pipeline", "Pipeline review"]),
    ("creativeDimension", ["Creative dimension status", "How's my creative side", "Creative progress"]),
]

DIMENSIONS = ["cognitive", "creative", "physiological", "behavioral", "knowledge", "reflection"]


def generate_level_system_examples(n=2000):
    """Generate Level System query examples."""
    examples = []

    for _ in range(n):
        query_type, templates = random.choice(LEVEL_QUERY_TYPES)
        template = random.choice(templates)

        # Some queries can have dimension specified
        params = {"query_type": query_type}

        if query_type == "dimensionStatus":
            dimension = random.choice(DIMENSIONS)
            params["dimension"] = dimension
            # Modify template to include dimension
            dimension_templates = [
                f"How's my {dimension} dimension",
                f"Show {dimension} status",
                f"What's my {dimension} progress",
                f"{dimension.capitalize()} dimension status",
            ]
            template = random.choice(dimension_templates)

        output = make_function_call("query_level_system", params)
        examples.append({"input": template, "output": output})

    return examples


# Deep Work templates
DEEP_WORK_DURATIONS = [
    (30, ["30 minutes", "half hour", "half an hour"]),
    (45, ["45 minutes"]),
    (60, ["1 hour", "an hour", "one hour", "60 minutes"]),
    (90, ["90 minutes", "hour and a half", "1.5 hours"]),
    (120, ["2 hours", "two hours", "couple hours"]),
    (180, ["3 hours", "three hours"]),
]


def generate_deep_work_examples(n=1000):
    """Generate Deep Work session examples."""
    examples = []

    # Start deep work templates
    start_templates = [
        "Start deep work",
        "Begin focus mode",
        "Let's do deep work",
        "Enter focus mode",
        "Start focused time",
        "Begin concentration mode",
        "Go into deep work",
        "I want to focus",
        "Time to focus",
        "Focus time",
        "Deep work mode",
        "Heads down time",
        "No distractions mode",
    ]

    start_with_duration_templates = [
        "Start deep work for {duration}",
        "Focus for {duration}",
        "Deep work {duration}",
        "Let's focus for {duration}",
        "Begin focus mode for {duration}",
        "{duration} of deep work",
        "I want to focus for {duration}",
    ]

    start_pomodoro_templates = [
        "Start pomodoro",
        "Pomodoro mode",
        "Begin pomodoro session",
        "Let's do pomodoro",
        "Start pomodoro deep work",
    ]

    # Stop deep work templates
    stop_templates = [
        "Stop deep work",
        "End focus mode",
        "Done focusing",
        "Stop focus mode",
        "End deep work",
        "Finish focus session",
        "Exit focus mode",
        "I'm done focusing",
        "End concentration mode",
        "Stop the timer",
    ]

    # Extend deep work templates
    extend_templates = [
        "Extend deep work by {duration}",
        "Add {duration} to focus time",
        "Extend focus {duration}",
        "Keep going for {duration} more",
        "Add {duration} more",
        "Continue for {duration}",
        "{duration} more of deep work",
    ]

    # Generate start examples (no duration)
    for _ in range(n // 4):
        template = random.choice(start_templates)
        output = make_function_call("start_deep_work", {})
        examples.append({"input": template, "output": output})

    # Generate start examples (with duration)
    for _ in range(n // 3):
        duration_mins, duration_texts = random.choice(DEEP_WORK_DURATIONS)
        duration_text = random.choice(duration_texts)
        template = random.choice(start_with_duration_templates).format(duration=duration_text)
        output = make_function_call("start_deep_work", {"duration_minutes": duration_mins})
        examples.append({"input": template, "output": output})

    # Generate pomodoro examples
    for _ in range(n // 10):
        template = random.choice(start_pomodoro_templates)
        output = make_function_call("start_deep_work", {"duration_minutes": 25, "pomodoro_mode": True})
        examples.append({"input": template, "output": output})

    # Generate stop examples
    for _ in range(n // 5):
        template = random.choice(stop_templates)
        output = make_function_call("stop_deep_work", {})
        examples.append({"input": template, "output": output})

    # Generate extend examples
    for _ in range(n // 6):
        duration_mins, duration_texts = random.choice(DEEP_WORK_DURATIONS)
        duration_text = random.choice(duration_texts)
        template = random.choice(extend_templates).format(duration=duration_text)
        output = make_function_call("extend_deep_work", {"additional_minutes": duration_mins})
        examples.append({"input": template, "output": output})

    return examples


# Journal entry types
JOURNAL_ENTRY_TYPES = [
    ("gratitude", [
        "I'm grateful for {content}",
        "Grateful for {content}",
        "Thankful for {content}",
        "I appreciate {content}",
        "Gratitude: {content}",
    ]),
    ("mood", [
        "I'm feeling {feeling}",
        "Feeling {feeling}",
        "My mood is {feeling}",
        "I feel {feeling} today",
    ]),
    ("learning", [
        "I learned that {content}",
        "Today I learned {content}",
        "Learned: {content}",
        "TIL {content}",
        "I discovered that {content}",
    ]),
    ("reflection", [
        "Reflecting on {content}",
        "I've been thinking about {content}",
        "Thought: {content}",
        "Reflection: {content}",
    ]),
    ("goal", [
        "My goal is to {content}",
        "I want to {content}",
        "Goal: {content}",
        "I'm aiming to {content}",
    ]),
    ("challenge", [
        "I'm struggling with {content}",
        "Challenge: {content}",
        "My challenge is {content}",
        "I'm working through {content}",
    ]),
    ("celebration", [
        "I achieved {content}",
        "Celebrating {content}",
        "Win: {content}",
        "I'm proud of {content}",
        "Victory: {content}",
    ]),
    ("intention", [
        "My intention today is {content}",
        "I intend to {content}",
        "Today I will {content}",
        "Setting intention: {content}",
    ]),
    ("freeform", [
        "Journal: {content}",
        "Note to self: {content}",
        "Dear diary: {content}",
        "{content}",  # Sometimes just the content
    ]),
]

GRATITUDE_CONTENT = [
    "my team", "my health", "my family", "good sleep", "productive day",
    "the sunshine", "my morning coffee", "finishing the project", "supportive friends",
    "learning something new", "a good workout", "peaceful morning", "nice weather",
]

FEELINGS = [
    "great", "amazing", "tired", "energized", "focused", "stressed", "calm",
    "happy", "productive", "creative", "motivated", "relaxed", "anxious",
    "excited", "peaceful", "content", "overwhelmed", "optimistic",
]

LEARNING_CONTENT = [
    "how to optimize database queries", "a new design pattern", "the importance of rest",
    "better communication skills", "time management techniques", "a new Swift feature",
    "how to handle errors gracefully", "the value of deep work", "how to prioritize",
]

GENERAL_CONTENT = [
    "my work-life balance", "improving my productivity", "building better habits",
    "being more present", "focusing on what matters", "taking care of my health",
    "learning new skills", "connecting with others", "simplifying my life",
]


def generate_journal_examples(n=1000):
    """Generate Journal command examples."""
    examples = []

    for _ in range(n):
        entry_type, templates = random.choice(JOURNAL_ENTRY_TYPES)
        template = random.choice(templates)

        # Select appropriate content
        if entry_type == "gratitude":
            content = random.choice(GRATITUDE_CONTENT)
        elif entry_type == "mood":
            content = random.choice(FEELINGS)
            template = template.replace("{content}", "{feeling}")
        elif entry_type == "learning":
            content = random.choice(LEARNING_CONTENT)
        else:
            content = random.choice(GENERAL_CONTENT)

        input_text = template.format(content=content, feeling=content)

        # Handle mood differently - title should reflect feeling
        if entry_type == "mood":
            title = f"Feeling {content}"
        else:
            title = content.capitalize() if len(content) < 50 else content[:47] + "..."

        params = {
            "atom_type": "journalEntry",
            "title": title,
            "metadata": {"entryType": entry_type}
        }

        output = make_function_call("create_atom", params)
        examples.append({"input": input_text, "output": output})

    return examples


# Workout types
WORKOUT_TYPES = [
    ("run", ["run", "running", "went for a run", "jogged", "jogging"]),
    ("walk", ["walk", "walked", "went for a walk", "walking"]),
    ("swim", ["swim", "swimming", "swam", "went swimming"]),
    ("cycle", ["bike", "cycling", "biked", "went cycling", "rode my bike"]),
    ("strength", ["lifted weights", "strength training", "weight training", "gym workout", "lifted"]),
    ("yoga", ["yoga", "did yoga", "yoga session"]),
    ("hiit", ["HIIT", "hiit workout", "interval training", "tabata"]),
]

EXERCISES = [
    "push ups", "pull ups", "squats", "deadlifts", "bench press",
    "lunges", "planks", "burpees", "jumping jacks", "sit ups",
]


def generate_workout_examples(n=500):
    """Generate workout logging examples."""
    examples = []

    workout_templates = [
        "Log {workout_type}",
        "I did a {workout_type}",
        "Just finished {workout_type}",
        "Completed {workout_type} workout",
        "{workout_type} done",
    ]

    workout_with_duration_templates = [
        "Log {duration} minute {workout_type}",
        "{workout_type} for {duration} minutes",
        "Did {duration} minutes of {workout_type}",
        "Just finished {duration} minute {workout_type}",
    ]

    run_with_distance_templates = [
        "Ran {distance} km",
        "Ran {distance} kilometers",
        "{distance} km run",
        "Went for a {distance} km run",
    ]

    strength_templates = [
        "Did {sets} sets of {reps} {exercise}",
        "{exercise} {sets} by {reps}",
        "Completed {sets} sets of {exercise}",
        "{reps} {exercise}",
    ]

    # Basic workout logs
    for _ in range(n // 3):
        workout_type, workout_texts = random.choice(WORKOUT_TYPES)
        workout_text = random.choice(workout_texts)
        template = random.choice(workout_templates).format(workout_type=workout_text)
        output = make_function_call("log_workout", {"workout_type": workout_type})
        examples.append({"input": template, "output": output})

    # Workout with duration
    for _ in range(n // 3):
        workout_type, workout_texts = random.choice(WORKOUT_TYPES)
        workout_text = random.choice(workout_texts)
        duration = random.choice([15, 20, 30, 45, 60, 90])
        template = random.choice(workout_with_duration_templates).format(
            workout_type=workout_text, duration=duration
        )
        output = make_function_call("log_workout", {
            "workout_type": workout_type,
            "duration_minutes": duration
        })
        examples.append({"input": template, "output": output})

    # Running with distance
    for _ in range(n // 6):
        distance = random.choice([3, 5, 7, 10, 15, 21])
        template = random.choice(run_with_distance_templates).format(distance=distance)
        output = make_function_call("log_workout", {
            "workout_type": "run",
            "distance_km": distance
        })
        examples.append({"input": template, "output": output})

    # Strength with sets/reps
    for _ in range(n // 6):
        exercise = random.choice(EXERCISES)
        sets = random.choice([3, 4, 5])
        reps = random.choice([8, 10, 12, 15, 20])
        template = random.choice(strength_templates).format(
            exercise=exercise, sets=sets, reps=reps
        )
        output = make_function_call("log_workout", {
            "workout_type": "strength",
            "exercise": exercise,
            "sets": sets,
            "reps": reps
        })
        examples.append({"input": template, "output": output})

    return examples


# Navigation destinations
NAVIGATION_DESTINATIONS = [
    ("home", ["go home", "open home", "show home", "home screen"]),
    ("today", ["go to today", "open today", "show today", "today view"]),
    ("projects", ["go to projects", "open projects", "show projects", "my projects"]),
    ("ideas", ["go to ideas", "open ideas", "show ideas", "idea list"]),
    ("tasks", ["go to tasks", "open tasks", "show tasks", "task list", "my tasks"]),
    ("schedule", ["go to schedule", "open schedule", "show schedule", "my calendar", "calendar"]),
    ("research", ["go to research", "open research", "show research"]),
    ("focus", ["go to focus", "open focus mode", "focus screen"]),
    ("settings", ["go to settings", "open settings", "settings"]),
    ("sanctuary", ["go to sanctuary", "open sanctuary", "sanctuary view", "show sanctuary"]),
    ("dashboard", ["go to dashboard", "open dashboard", "show dashboard", "main dashboard"]),
    # NEW: Modern CosmoOS navigation destinations
    ("plannerum", ["go to plannerum", "open plannerum", "show plannerum", "planner", "plan", "planning", "open planner", "go to planner"]),
    ("thinkspace", ["go to thinkspace", "open thinkspace", "show thinkspace", "canvas", "think", "open canvas", "go to canvas", "thinking space"]),
    ("inbox", ["go to inbox", "open inbox", "show inbox", "my inbox", "inbox view"]),
    ("notes", ["go to notes", "open notes", "show notes", "my notes", "notes view"]),
]


def generate_navigation_examples(n=600):
    """Generate navigation examples."""
    examples = []

    for _ in range(n):
        destination, templates = random.choice(NAVIGATION_DESTINATIONS)
        template = random.choice(templates)
        output = make_function_call("navigate", {"destination": destination})
        examples.append({"input": template, "output": output})

    return examples


def format_for_mlx_lm(examples):
    """Format examples for MLX-LM fine-tuning with FunctionGemma chat format.

    Uses FunctionGemma's expected roles: developer, user, model
    """
    formatted = []

    for ex in examples:
        # For FunctionGemma, output is already formatted as the function call string
        output = ex["output"] if isinstance(ex["output"], str) else make_function_call_from_dict(ex["output"])

        formatted.append({
            "messages": [
                {"role": "developer", "content": FUNCTIONGEMMA_SYSTEM_PROMPT},
                {"role": "user", "content": ex["input"]},
                {"role": "model", "content": output}
            ]
        })

    return formatted


def make_function_call_from_dict(output_dict):
    """Convert old-style dict output to FunctionGemma format (for backwards compat)."""
    action = output_dict.get("action")

    if action == "create":
        atom_type = output_dict.get("type", "idea")
        params = {"atom_type": atom_type, "title": output_dict.get("title", "Untitled")}
        if "body" in output_dict:
            params["body"] = output_dict["body"]
        if "metadata" in output_dict:
            params["metadata"] = output_dict["metadata"]
        if "links" in output_dict:
            params["links"] = output_dict["links"]
        return make_function_call("create_atom", params)

    elif action == "update":
        params = {"target": output_dict.get("target", "context")}
        if "title" in output_dict:
            params["title"] = output_dict["title"]
        if "body" in output_dict:
            params["body"] = output_dict["body"]
        if "metadata" in output_dict:
            params["metadata"] = output_dict["metadata"]
        if "links" in output_dict:
            params["links"] = output_dict["links"]
        return make_function_call("update_atom", params)

    elif action == "delete":
        return make_function_call("delete_atom", {"target": output_dict.get("target", "context")})

    elif action == "search":
        params = {}
        if "query" in output_dict:
            params["query"] = output_dict["query"]
        if "type" in output_dict:
            params["types"] = [output_dict["type"]]
        if "filter" in output_dict:
            # Flatten filters into params
            for k, v in output_dict["filter"].items():
                params[k] = v
        if "mode" in output_dict:
            params["mode"] = output_dict["mode"]
        if "target" in output_dict:
            params["target"] = output_dict["target"]
        return make_function_call("search_atoms", params)

    elif action == "batch":
        items = []
        for item in output_dict.get("items", []):
            item_dict = {
                "atom_type": item.get("type", "task"),
                "title": item.get("title", "Untitled")
            }
            if "links" in item:
                item_dict["links"] = item["links"]
            items.append(item_dict)
        return make_function_call("batch_create", {"items": items})

    elif action == "navigate":
        return make_function_call("navigate", {"destination": output_dict.get("destination", "home")})

    else:
        # Fallback
        return make_function_call("create_atom", {"atom_type": "idea", "title": "Unknown"})


def validate_examples(examples):
    """Validate all examples have valid structure."""
    valid_functions = {
        "create_atom", "update_atom", "delete_atom", "search_atoms",
        "batch_create", "navigate", "query_level_system",
        "start_deep_work", "stop_deep_work", "extend_deep_work",
        "log_workout", "trigger_correlation_analysis"
    }

    issues = []
    for i, ex in enumerate(examples):
        output = ex.get("output", "")

        # For new FunctionGemma format (string)
        if isinstance(output, str):
            # Check it has proper format
            if not output.startswith("<start_function_call>"):
                issues.append(f"Example {i}: Missing <start_function_call> prefix")
            elif not output.endswith("<end_function_call>"):
                issues.append(f"Example {i}: Missing <end_function_call> suffix")
            else:
                # Extract function name
                import re
                match = re.search(r"call:(\w+)\{", output)
                if match:
                    func_name = match.group(1)
                    if func_name not in valid_functions:
                        issues.append(f"Example {i}: Unknown function '{func_name}'")
                else:
                    issues.append(f"Example {i}: Could not parse function name")
        # For old dict format (backwards compat)
        elif isinstance(output, dict):
            action = output.get("action")
            valid_actions = {"create", "update", "delete", "search", "batch", "navigate"}
            if action and action not in valid_actions:
                issues.append(f"Example {i}: Invalid action '{action}'")

    return issues


def main():
    print("🎯 CosmoOS FunctionGemma Training Data Generator v3")
    print("=" * 60)
    print("Generating 15,000+ examples for FunctionGemma 270M fine-tuning")
    print("Output format: <start_function_call>call:FUNC{params}<end_function_call>")

    # Generate all categories
    print("\n📝 Generating training examples...")

    simple_examples = generate_simple_creation_examples(4000)
    print(f"  ✓ Simple entity creation: {len(simple_examples)} examples")

    project_examples = generate_project_specific_examples(2500)
    print(f"  ✓ Project-specific creation: {len(project_examples)} examples")

    timed_examples = generate_timed_creation_examples(2000)
    print(f"  ✓ Timed entity creation: {len(timed_examples)} examples")

    modification_examples = generate_modification_examples(1500)
    print(f"  ✓ Entity modification: {len(modification_examples)} examples")

    level_system_examples = generate_level_system_examples(2000)
    print(f"  ✓ Level System queries: {len(level_system_examples)} examples")

    deep_work_examples = generate_deep_work_examples(1000)
    print(f"  ✓ Deep Work commands: {len(deep_work_examples)} examples")

    journal_examples = generate_journal_examples(1000)
    print(f"  ✓ Journal entries: {len(journal_examples)} examples")

    workout_examples = generate_workout_examples(500)
    print(f"  ✓ Workout logging: {len(workout_examples)} examples")

    navigation_examples = generate_navigation_examples(600)
    print(f"  ✓ Navigation: {len(navigation_examples)} examples")

    batch_examples = generate_batch_examples(500)
    print(f"  ✓ Multi-entity / brain dump: {len(batch_examples)} examples")

    # Combine all examples
    all_examples = (
        simple_examples +
        project_examples +
        timed_examples +
        modification_examples +
        level_system_examples +
        deep_work_examples +
        journal_examples +
        workout_examples +
        navigation_examples +
        batch_examples
    )

    print(f"\n📊 Total examples: {len(all_examples)}")

    # Validate
    print("\n🔍 Validating examples...")
    issues = validate_examples(all_examples)
    if issues:
        print(f"  ⚠️  Found {len(issues)} validation issues:")
        for issue in issues[:10]:  # Show first 10
            print(f"     - {issue}")
        if len(issues) > 10:
            print(f"     ... and {len(issues) - 10} more")
    else:
        print("  ✓ All examples valid!")

    # Shuffle
    random.shuffle(all_examples)

    # Split into train/validation
    split_idx = int(len(all_examples) * 0.9)
    train_examples = all_examples[:split_idx]
    valid_examples = all_examples[split_idx:]

    print(f"\n📁 Split: {len(train_examples)} train, {len(valid_examples)} validation")

    # Format for MLX-LM
    train_formatted = format_for_mlx_lm(train_examples)
    valid_formatted = format_for_mlx_lm(valid_examples)

    # Write files
    print("\n💾 Writing files...")

    train_path = OUTPUT_DIR / "train.jsonl"
    with open(train_path, "w") as f:
        for ex in train_formatted:
            f.write(json.dumps(ex) + "\n")
    print(f"  ✓ {train_path}")

    valid_path = OUTPUT_DIR / "valid.jsonl"
    with open(valid_path, "w") as f:
        for ex in valid_formatted:
            f.write(json.dumps(ex) + "\n")
    print(f"  ✓ {valid_path}")

    # Write raw examples for inspection (include project-specific examples prominently)
    raw_path = OUTPUT_DIR / "examples_raw.json"
    # Get first 50 simple + first 50 project-specific for good coverage
    sample_examples = simple_examples[:50] + project_examples[:50]
    random.shuffle(sample_examples)
    with open(raw_path, "w") as f:
        json.dump(sample_examples, f, indent=2)
    print(f"  ✓ {raw_path} (100 samples for inspection)")

    print("\n✅ Training data generation complete!")
    print(f"\n📌 FunctionGemma output format:")
    print(f"   <start_function_call>call:FUNC_NAME{{params}}<end_function_call>")
    print(f"\n📌 Key patterns now supported:")
    print(f"   • 'Idea for Michael about marketing' → create_atom with project link")
    print(f"   • 'What's my level?' → query_level_system{{query_type:levelStatus}}")
    print(f"   • 'Start deep work for 2 hours' → start_deep_work{{duration_minutes:120}}")
    print(f"   • 'I'm grateful for my team' → create_atom journalEntry with gratitude type")
    print(f"   • 'Log 5km run' → log_workout{{workout_type:run,distance_km:5}}")
    print(f"\n📌 Next steps:")
    print(f"   1. Review samples in {OUTPUT_DIR}/examples_raw.json")
    print(f"   2. Download FunctionGemma 270M:")
    print(f"      huggingface-cli download google/functiongemma-270m-it")
    print(f"   3. Convert to MLX format:")
    print(f"      python -m mlx_lm.convert \\")
    print(f"        --hf-path google/functiongemma-270m-it \\")
    print(f"        --mlx-path ./models/functiongemma-270m-mlx")
    print(f"   4. Run fine-tuning with MLX-LM LoRA:")
    print(f"      python -m mlx_lm.lora \\")
    print(f"        --model ./models/functiongemma-270m-mlx \\")
    print(f"        --data {OUTPUT_DIR} \\")
    print(f"        --train \\")
    print(f"        --batch-size 4 \\")
    print(f"        --lora-rank 16 \\")
    print(f"        --lora-alpha 32 \\")
    print(f"        --epochs 3 \\")
    print(f"        --output ./models/functiongemma-270m-cosmo-v1")


if __name__ == "__main__":
    main()
