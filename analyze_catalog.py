#!/usr/bin/env python3
"""
Comprehensive Catalog Data Analysis Script
Analyzes University at Buffalo catalog CSV for data quality issues
"""

import csv
import re
import json
from collections import defaultdict, Counter
from pathlib import Path
from typing import Dict, List, Set, Tuple
import sys

class CatalogAnalyzer:
    def __init__(self, csv_path: str):
        self.csv_path = csv_path
        self.rows = []
        self.headers = []
        self.issues = defaultdict(list)
        self.stats = defaultdict(int)
        self.audit_rows = []
        self.normal_rows = []
        
    def load_data(self):
        """Load CSV data"""
        print(f"Loading {self.csv_path}...")
        with open(self.csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            self.headers = reader.fieldnames
            self.rows = list(reader)
        print(f"✓ Loaded {len(self.rows)} rows\n")
        
    def categorize_rows(self):
        """Separate AUDIT rows from normal rows"""
        for idx, row in enumerate(self.rows):
            if row.get('Course Code', '').upper() == 'AUDIT':
                self.audit_rows.append((idx, row))
            else:
                self.normal_rows.append((idx, row))
        
        self.stats['total_rows'] = len(self.rows)
        self.stats['audit_rows'] = len(self.audit_rows)
        self.stats['normal_rows'] = len(self.normal_rows)
        
    def analyze_course_codes(self):
        """Analyze course code patterns and validity"""
        print("=" * 80)
        print("COURSE CODE ANALYSIS")
        print("=" * 80)
        
        # Valid course code pattern: 3-4 letters, space, 3 digits, optional letter
        valid_pattern = re.compile(r'^[A-Z]{2,4}\s\d{3}[A-Z]?$')
        invalid_codes = []
        code_frequencies = Counter()
        
        for idx, row in self.normal_rows:
            code = row.get('Course Code', '').strip()
            if code:
                code_frequencies[code] += 1
                if not valid_pattern.match(code):
                    invalid_codes.append((idx + 2, code, row.get('Course Title', '')[:50]))
        
        print(f"\nTotal unique course codes: {len(code_frequencies)}")
        print(f"Invalid course code formats: {len(invalid_codes)}")
        
        if invalid_codes:
            print("\nInvalid Course Codes (showing first 20):")
            for row_num, code, title in invalid_codes[:20]:
                print(f"  Row {row_num}: '{code}' - {title}")
        
        # Check for duplicates
        duplicates = [(code, count) for code, count in code_frequencies.items() if count > 50]
        if duplicates:
            print(f"\nSuspicious duplicate codes (>50 occurrences):")
            for code, count in sorted(duplicates, key=lambda x: x[1], reverse=True)[:10]:
                print(f"  {code}: {count} times")
        
        self.issues['invalid_course_codes'] = invalid_codes
        return len(invalid_codes)
    
    def analyze_credits(self):
        """Analyze credit values including ranges"""
        print("\n" + "=" * 80)
        print("CREDITS ANALYSIS")
        print("=" * 80)
        
        missing_credits = []
        invalid_credits = []
        credit_patterns = Counter()
        credit_ranges = []
        
        # Valid patterns: "3", "1-6", "0-12", etc.
        valid_credit_pattern = re.compile(r'^\d+(-\d+)?$')
        
        for idx, row in self.normal_rows:
            credits = row.get('Credits', '').strip()
            
            if not credits:
                missing_credits.append((idx + 2, row.get('Course Code', ''), row.get('Course Title', '')[:50]))
            elif not valid_credit_pattern.match(credits):
                invalid_credits.append((idx + 2, credits, row.get('Course Code', '')))
            else:
                credit_patterns[credits] += 1
                if '-' in credits:
                    credit_ranges.append((idx + 2, credits, row.get('Course Code', '')))
        
        print(f"\nMissing credits: {len(missing_credits)}")
        print(f"Invalid credit formats: {len(invalid_credits)}")
        print(f"Credit ranges found: {len(credit_ranges)}")
        
        if missing_credits:
            print("\nRows with missing credits (first 15):")
            for row_num, code, title in missing_credits[:15]:
                print(f"  Row {row_num}: {code} - {title}")
        
        if invalid_credits:
            print("\nInvalid credit values (first 15):")
            for row_num, credits, code in invalid_credits[:15]:
                print(f"  Row {row_num}: '{credits}' for {code}")
        
        print(f"\nCredit value distribution (top 10):")
        for credits, count in credit_patterns.most_common(10):
            print(f"  {credits} credits: {count} courses")
        
        self.issues['missing_credits'] = missing_credits
        self.issues['invalid_credits'] = invalid_credits
        return len(missing_credits) + len(invalid_credits)
    
    def analyze_departments(self):
        """Analyze department assignments"""
        print("\n" + "=" * 80)
        print("DEPARTMENT ANALYSIS")
        print("=" * 80)
        
        missing_dept = []
        dept_distribution = Counter()
        programs_by_dept = defaultdict(set)
        
        for idx, row in enumerate(self.rows):
            dept = row.get('Department', '').strip()
            program = row.get('Degree Name', '').strip()
            degree_type = row.get('Degree Type', '').strip()
            
            if not dept:
                missing_dept.append((idx + 2, program, degree_type))
            else:
                dept_distribution[dept] += 1
                programs_by_dept[dept].add(program)
        
        print(f"\nTotal departments: {len(dept_distribution)}")
        print(f"Programs missing department: {len(set(p for _, p, _ in missing_dept))}")
        print(f"Rows missing department: {len(missing_dept)}")
        
        if missing_dept:
            # Group by program
            missing_programs = defaultdict(list)
            for row_num, program, deg_type in missing_dept:
                missing_programs[(program, deg_type)].append(row_num)
            
            print("\nPrograms missing department assignment:")
            for (program, deg_type), rows in sorted(missing_programs.items()):
                print(f"  {program} ({deg_type}): {len(rows)} rows")
        
        print(f"\nDepartment distribution (top 15):")
        for dept, count in dept_distribution.most_common(15):
            print(f"  {dept}: {count} rows, {len(programs_by_dept[dept])} programs")
        
        self.issues['missing_departments'] = missing_dept
        return len(missing_dept)
    
    def analyze_audit_rows(self):
        """Deep analysis of AUDIT rows"""
        print("\n" + "=" * 80)
        print("AUDIT ROWS ANALYSIS")
        print("=" * 80)
        
        print(f"\nTotal AUDIT rows: {len(self.audit_rows)}")
        
        if not self.audit_rows:
            print("No AUDIT rows found!")
            return 0
        
        # Categorize AUDIT issues
        audit_categories = {
            'missing_credits': [],
            'missing_title': [],
            'missing_description': [],
            'invalid_json_selectfrom': [],
            'empty_category': [],
            'other': []
        }
        
        for idx, row in self.audit_rows:
            issues_found = []
            
            # Check credits
            if not row.get('Credits', '').strip():
                audit_categories['missing_credits'].append(idx + 2)
                issues_found.append('no_credits')
            
            # Check title
            if not row.get('Course Title', '').strip():
                audit_categories['missing_title'].append(idx + 2)
                issues_found.append('no_title')
            
            # Check description
            if not row.get('Course Description', '').strip():
                audit_categories['missing_description'].append(idx + 2)
                issues_found.append('no_desc')
            
            # Check requirement category
            category = row.get('Requirement Category', '').strip()
            if not category or category == 'None':
                audit_categories['empty_category'].append(idx + 2)
                issues_found.append('no_category')
            
            # Check for malformed selectFrom JSON
            if row.get('Mode', '') == 'selectFrom':
                desc = row.get('Course Description', '')
                if desc and not desc.strip().startswith('['):
                    audit_categories['invalid_json_selectfrom'].append(idx + 2)
                    issues_found.append('bad_json')
            
            if not issues_found:
                audit_categories['other'].append(idx + 2)
        
        print("\nAUDIT Row Categories:")
        for category, row_nums in audit_categories.items():
            if row_nums:
                print(f"  {category}: {len(row_nums)} rows")
        
        # Show examples from each category
        print("\nAUDIT Row Examples:")
        for category, row_nums in audit_categories.items():
            if row_nums:
                print(f"\n  {category} (Row {row_nums[0]}):")
                # Find the row
                for idx, row in self.audit_rows:
                    if idx + 2 == row_nums[0]:
                        print(f"    Program: {row.get('Degree Name', 'N/A')}")
                        print(f"    Category: {row.get('Requirement Category', 'N/A')}")
                        print(f"    Mode: {row.get('Mode', 'N/A')}")
                        print(f"    Credits: '{row.get('Credits', '')}'")
                        print(f"    Title: '{row.get('Course Title', '')[:60]}'")
                        desc = row.get('Course Description', '')
                        print(f"    Description: '{desc[:80]}...' ({len(desc)} chars)")
                        break
        
        self.issues['audit_categories'] = audit_categories
        return len(self.audit_rows)
    
    def analyze_programs(self):
        """Analyze program-level data"""
        print("\n" + "=" * 80)
        print("PROGRAM ANALYSIS")
        print("=" * 80)
        
        programs = defaultdict(lambda: {
            'rows': 0,
            'departments': set(),
            'degree_types': set(),
            'catoids': set(),
            'has_audit': False
        })
        
        for idx, row in enumerate(self.rows):
            program = row.get('Degree Name', '').strip()
            if program:
                programs[program]['rows'] += 1
                
                dept = row.get('Department', '').strip()
                if dept:
                    programs[program]['departments'].add(dept)
                
                deg_type = row.get('Degree Type', '').strip()
                if deg_type:
                    programs[program]['degree_types'].add(deg_type)
                
                catoid = row.get('Source Catoid', '').strip()
                if catoid:
                    programs[program]['catoids'].add(catoid)
                
                if row.get('Course Code', '').upper() == 'AUDIT':
                    programs[program]['has_audit'] = True
        
        print(f"\nTotal programs: {len(programs)}")
        
        # Programs with issues
        multi_dept = [(p, data) for p, data in programs.items() if len(data['departments']) > 1]
        no_dept = [(p, data) for p, data in programs.items() if len(data['departments']) == 0]
        with_audit = [(p, data) for p, data in programs.items() if data['has_audit']]
        
        print(f"Programs with multiple departments: {len(multi_dept)}")
        print(f"Programs with no department: {len(no_dept)}")
        print(f"Programs with AUDIT rows: {len(with_audit)}")
        
        if no_dept:
            print("\nPrograms missing department (first 10):")
            for program, data in sorted(no_dept, key=lambda x: x[1]['rows'], reverse=True)[:10]:
                degree_type = list(data['degree_types'])[0] if data['degree_types'] else 'Unknown'
                print(f"  {program} ({degree_type}): {data['rows']} rows")
        
        if multi_dept:
            print("\nPrograms with multiple departments:")
            for program, data in multi_dept[:10]:
                print(f"  {program}: {', '.join(sorted(data['departments']))}")
        
        # Graduate vs Undergraduate
        undergrad = sum(1 for p, d in programs.items() if any('Undergraduate' in dt for dt in d['degree_types']))
        grad = sum(1 for p, d in programs.items() if any('Graduate' in dt or 'Masters' in dt or 'Doctoral' in dt for dt in d['degree_types']))
        
        print(f"\nProgram level distribution:")
        print(f"  Undergraduate: {undergrad}")
        print(f"  Graduate: {grad}")
        
        return len(no_dept)
    
    def analyze_modes(self):
        """Analyze requirement modes"""
        print("\n" + "=" * 80)
        print("REQUIREMENT MODE ANALYSIS")
        print("=" * 80)
        
        mode_counts = Counter()
        mode_by_category = defaultdict(Counter)
        
        for idx, row in enumerate(self.rows):
            mode = row.get('Mode', '').strip()
            category = row.get('Requirement Category', '').strip()
            
            if mode:
                mode_counts[mode] += 1
                if category:
                    mode_by_category[category][mode] += 1
        
        print(f"\nMode distribution:")
        for mode, count in mode_counts.most_common():
            print(f"  {mode}: {count}")
        
        # Check selectFrom validity
        selectfrom_rows = [(idx, row) for idx, row in enumerate(self.rows) if row.get('Mode', '') == 'selectFrom']
        invalid_selectfrom = []
        
        for idx, row in selectfrom_rows:
            desc = row.get('Course Description', '').strip()
            if desc:
                try:
                    data = json.loads(desc)
                    if not isinstance(data, list):
                        invalid_selectfrom.append((idx + 2, 'not_array'))
                except json.JSONDecodeError as e:
                    invalid_selectfrom.append((idx + 2, str(e)[:50]))
        
        print(f"\nselectFrom rows: {len(selectfrom_rows)}")
        print(f"Invalid selectFrom JSON: {len(invalid_selectfrom)}")
        
        if invalid_selectfrom:
            print("\nInvalid selectFrom rows (first 10):")
            for row_num, error in invalid_selectfrom[:10]:
                print(f"  Row {row_num}: {error}")
        
        self.issues['invalid_selectfrom'] = invalid_selectfrom
        return len(invalid_selectfrom)
    
    def cross_reference_check(self):
        """Cross-reference courses mentioned in selectFrom"""
        print("\n" + "=" * 80)
        print("CROSS-REFERENCE VALIDATION")
        print("=" * 80)
        
        # Build course inventory
        course_inventory = set()
        for idx, row in self.normal_rows:
            code = row.get('Course Code', '').strip()
            if code and code.upper() != 'AUDIT':
                course_inventory.add(code)
        
        print(f"\nCourse inventory: {len(course_inventory)} unique courses")
        
        # Check selectFrom references
        missing_courses = []
        selectfrom_rows = [(idx, row) for idx, row in enumerate(self.rows) if row.get('Mode', '') == 'selectFrom']
        
        for idx, row in selectfrom_rows:
            desc = row.get('Course Description', '').strip()
            if desc:
                try:
                    data = json.loads(desc)
                    if isinstance(data, list):
                        for item in data:
                            if isinstance(item, dict):
                                code = item.get('code', '').strip()
                                if code and code not in course_inventory and code.upper() != 'AUDIT':
                                    missing_courses.append((idx + 2, code, row.get('Degree Name', '')))
                except:
                    pass
        
        print(f"Missing course references in selectFrom: {len(missing_courses)}")
        
        if missing_courses:
            print("\nMissing courses (first 15):")
            for row_num, code, program in missing_courses[:15]:
                print(f"  Row {row_num}: {code} (in {program[:50]})")
        
        self.issues['missing_course_references'] = missing_courses
        return len(missing_courses)
    
    def generate_summary(self):
        """Generate final summary"""
        print("\n" + "=" * 80)
        print("SUMMARY")
        print("=" * 80)
        
        total_issues = 0
        
        print(f"\nDataset Overview:")
        print(f"  Total rows: {self.stats['total_rows']:,}")
        print(f"  Normal rows: {self.stats['normal_rows']:,}")
        print(f"  AUDIT rows: {self.stats['audit_rows']:,}")
        
        print(f"\nIssues Found:")
        issue_counts = {
            'Invalid course codes': len(self.issues.get('invalid_course_codes', [])),
            'Missing credits': len(self.issues.get('missing_credits', [])),
            'Invalid credits': len(self.issues.get('invalid_credits', [])),
            'Missing departments': len(self.issues.get('missing_departments', [])),
            'Invalid selectFrom JSON': len(self.issues.get('invalid_selectfrom', [])),
            'Missing course references': len(self.issues.get('missing_course_references', []))
        }
        
        for issue_type, count in issue_counts.items():
            if count > 0:
                print(f"  {issue_type}: {count}")
                total_issues += count
        
        print(f"\n  TOTAL ISSUES: {total_issues}")
        
        if self.audit_rows:
            print(f"\nAUDIT Row Breakdown:")
            audit_cats = self.issues.get('audit_categories', {})
            for category, rows in audit_cats.items():
                if rows:
                    print(f"  {category}: {len(rows)}")
        
        # Data quality score
        if self.stats['total_rows'] > 0:
            error_rate = (total_issues / self.stats['total_rows']) * 100
            quality_score = max(0, 100 - error_rate)
            print(f"\nData Quality Score: {quality_score:.1f}%")
        
        print("\n" + "=" * 80)
    
    def run(self):
        """Run complete analysis"""
        self.load_data()
        self.categorize_rows()
        
        self.analyze_course_codes()
        self.analyze_credits()
        self.analyze_departments()
        self.analyze_programs()
        self.analyze_modes()
        self.analyze_audit_rows()
        self.cross_reference_check()
        
        self.generate_summary()

def main():
    csv_file = Path.home() / "Desktop" / "University_at_Buffalo_scraped_catalog_1767848373.csv"
    
    if not csv_file.exists():
        print(f"Error: File not found: {csv_file}")
        return 1
    
    analyzer = CatalogAnalyzer(str(csv_file))
    analyzer.run()
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
